import AudioIO
import BroadcastWave
import Destinations
import Foundation
import MixerLink
import Observation
import ShowReport
import Synchronization

/// The recorder. While Armed it receives audio from a device and keeps meters for every USB Channel.
/// While recording it writes a Take: one Stem per USB Channel in the open Show.
@MainActor
@Observable
public final class Recorder {
    public private(set) var isArmed = false
    public private(set) var isRecording = false
    public private(set) var usbChannelCount = 0
    /// The open Show, if any. Created on the first record press.
    public private(set) var currentShow: Show?
    /// Markers placed in the current (or last) Take.
    public private(set) var takeMarkers: [TakeMetadata.Marker] = []
    /// Whether the last Take was ended by the recorder because the last healthy Destination was about to fill.
    public private(set) var endedForLackOfSpace = false

    /// The Device Destination: Documents/Shows.
    public static var defaultDeviceFolder: URL {
        URL.documentsDirectory.appending(path: "Shows", directoryHint: .isDirectory)
    }

    @ObservationIgnored private let deviceFolder: URL
    @ObservationIgnored private let driveFolder: () -> DestinationAccess?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let freeSpace: (URL) -> Int64
    @ObservationIgnored private let makeStem: (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink
    @ObservationIgnored private var device: (any AudioIODevice)?
    @ObservationIgnored private var capture: Capture?
    @ObservationIgnored private var writers: [TakeWriter] = []
    @ObservationIgnored private var driveAccess: DestinationAccess?
    /// The running Take's metadata and folders (one per Copy), and the ring position it started at.
    @ObservationIgnored private var take: (metadata: TakeMetadata, folders: [URL], startFrame: Int, stems: [StemSpec], info: StemWriter.Info)?
    /// How each Copy of the last Take ended up, for after it stops.
    @ObservationIgnored private var finishedCopies: [DestinationKind: CopyStatus] = [:]

    /// - Parameters:
    ///   - deviceFolder: where the Device Copy of every Show goes.
    ///   - driveFolder: asked at each record press for the Drive folder; nil writes to the Device only.
    public init(
        deviceFolder: URL = Recorder.defaultDeviceFolder,
        driveFolder: @escaping () -> DestinationAccess? = { nil },
        now: @escaping () -> Date = Date.init,
        freeSpace: @escaping (URL) -> Int64 = { DriveFolderStore.availableBytes(at: $0) },
        makeStem: @escaping (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink = { try StemWriter.open(url: $0, info: $1, resumingAt: $2) }
    ) {
        self.freeSpace = freeSpace
        self.makeStem = makeStem
        self.deviceFolder = deviceFolder
        self.driveFolder = driveFolder
        self.now = now
    }

    /// Starts receiving audio from `device`. Any previously Armed device is stopped first.
    public func arm(_ device: any AudioIODevice) throws {
        disarm()
        let capture = Capture(channelCount: device.inputChannelCount, sampleRate: device.sampleRate)
        try device.start(input: { block in capture.receive(block) })
        self.device = device
        self.capture = capture
        usbChannelCount = device.inputChannelCount
        isArmed = true
    }

    /// Restarts input on the Armed device after the system stopped it (an audio session
    /// interruption), without ending a running Take.
    ///
    /// Frames the device never delivered while it was stopped are not in the Take: the Stems carry
    /// on from the next frame that arrives.
    public func restartInput() throws {
        guard let device, let capture else { throw RecorderError.notArmed }
        try device.start(input: { block in capture.receive(block) })
    }

    /// Moves input to `replacement` (for example a freshly configured device after the system
    /// reset its media services).
    ///
    /// When `replacement` has the same USB Channel count and sample rate, the running Take carries
    /// on into the same Stems and this returns `true`. Otherwise the Take is stopped and finalized,
    /// the recorder Arms on `replacement`, and this returns `false`.
    @discardableResult
    public func restartInput(on replacement: any AudioIODevice) throws -> Bool {
        guard let device, let capture,
              replacement.inputChannelCount == capture.channelCount,
              replacement.sampleRate == device.sampleRate
        else {
            try arm(replacement)
            return false
        }
        device.stop()
        self.device = replacement
        try replacement.start(input: { block in capture.receive(block) })
        return true
    }

    /// Stops any Take, stops the device and clears the meters.
    public func disarm() {
        if isRecording { try? stopTake() }
        device?.stop()
        device = nil
        capture = nil
        usbChannelCount = 0
        isArmed = false
    }

    /// Frames lost since Arming because the writer couldn't keep up. (Dropouts proper come in #15.)
    public var droppedFrameCount: Int {
        capture?.rings.map { $0.overflowedFrames.load(ordering: .relaxed) }.max() ?? 0
    }

    /// Frames captured but not yet written to the Stems, for the slowest Destination.
    var bufferedFrameCount: Int {
        capture?.rings.map(\.availableFrames).max() ?? 0
    }

    /// Each USB Channel's linear peak level (0...1) since the last call. Empty when not Armed.
    public func takeMeterLevels() -> [Float] {
        capture?.meters.take() ?? []
    }

    /// Starts a Take in the open Show, creating a Show first if none is open.
    ///
    /// `sources` are frozen into the Take: Stem names and bext descriptions use them, and later
    /// changes on the Mixer don't touch this Take's files. USB Channels without a Source get "USB NN".
    public func startTake(sources: [Source] = []) throws {
        guard let device, let capture else { throw RecorderError.notArmed }
        guard !isRecording else { return }
        let date = now()

        let drive = driveFolder()
        var show: Show
        do {
            if var open = currentShow {
                try open.useDrive(drive?.folder)
                show = open
            } else {
                show = try Show.create(in: deviceFolder, drive: drive?.folder, on: date)
            }
        } catch {
            drive?.release()
            throw error
        }
        let takeFolders = try show.createNextTakeFolder()

        let sampleRate = Int(device.sampleRate.rounded())
        let timeReference = UInt64(date.timeIntervalSince(Calendar.current.startOfDay(for: date)) * Double(sampleRate))
        let resolved = (0..<capture.channelCount).map { channel in
            sources.indices.contains(channel) ? sources[channel] : .fallback(usbChannel: channel + 1)
        }
        let channels = resolved.enumerated().map { index, source in
            TakeMetadata.USBChannel(usbChannel: index + 1, stemFile: StemFileName.make(usbChannel: index + 1, sourceName: source.name), source: source)
        }
        let metadata = TakeMetadata(
            show: show.name, take: show.takeCount, startedAt: date, sampleRate: sampleRate,
            timeReference: timeReference, usbChannels: channels)

        // One writer per Copy, each draining its own ring, so a slow Drive never holds up the Device.
        let specs = zip(channels, resolved).map { StemSpec(file: $0.stemFile, description: $1.name) }
        let info = StemWriter.Info(sampleRate: sampleRate, description: "", originator: "ShowRecorder", timeReference: timeReference, originationDate: date)
        var writers: [TakeWriter] = []
        for (copy, takeFolder) in takeFolders.enumerated() {
            let stems = try specs.map { try makeStem(takeFolder.appending(path: $0.file), info.described($0.description), nil) }
            try metadata.write(to: takeFolder)
            writers.append(TakeWriter(ring: capture.rings[copy], stems: stems, commitInterval: sampleRate * 2, onFailure: { [weak self] in
                capture.disable(copy: copy)
                Task { @MainActor in self?.copyFailed() }
            }))
        }

        for (copy, writer) in writers.enumerated() {
            capture.rings[copy].discardAll()
            capture.rings[copy].joinFrame.store(0, ordering: .releasing)
            writer.start()
        }
        take = (metadata, takeFolders, capture.rings[0].totalWrittenFrames, specs, info)
        finishedCopies = [:]
        takeMarkers = []
        endedForLackOfSpace = false
        capture.startCapturing(copies: writers.count)

        self.writers = writers
        driveAccess = takeFolders.count > 1 ? drive : nil
        if takeFolders.count == 1 { drive?.release() }
        currentShow = show
        isRecording = true
    }

    /// Places a Marker at the Take's current sample position (frames written so far), in every Stem
    /// of every Copy and in `Take.json`. Does nothing when no Take is running.
    public func addMarker(named name: String? = nil) {
        guard isRecording, let capture, var take else { return }
        let position = capture.rings[0].totalWrittenFrames - take.startFrame
        let marker = TakeMetadata.Marker(position: position, name: name ?? "Marker \(takeMarkers.count + 1)", origin: .operator)
        takeMarkers.append(marker)
        take.metadata.markers = takeMarkers
        self.take = take
        // Take.json first: it's written whole and atomically, so a Marker survives even if the Stems'
        // next header commit never happens.
        for folder in take.folders { try? take.metadata.write(to: folder) }
        let stemMarkers = takeMarkers.map { StemMarker(position: UInt32(clamping: $0.position), label: $0.name) }
        for writer in writers { writer.setMarkers(stemMarkers) }
    }

    /// How `kind`'s Copy of the current (or last) Take is doing. A Copy that never started is missing.
    public func copyStatus(_ kind: DestinationKind) -> CopyStatus {
        guard isRecording else { return finishedCopies[kind] ?? .missing }
        let index = kind == .device ? 0 : 1
        guard writers.indices.contains(index) else { return .missing }
        return writers[index].hasFailed ? .interrupted : .recording
    }

    /// Looks for a Destination that has become available since the Take started. A Drive that appears
    /// joins the running Take: its Stems start with silence up to the join point, which is recorded as
    /// a Gap in `Take.json` on both Copies. Call it regularly while recording.
    public func checkDestinations() {
        guard isRecording, let capture, var show = currentShow, var take else { return }

        // Keep 60 s of audio free on each Destination. A Copy that's short stops cleanly while another
        // has room; when the last healthy one is short the Take finalizes, before anything fills.
        let reserve = Int64(60 * take.metadata.usbChannels.count * take.info.sampleRate * 3)
        let healthy = writers.indices.filter { !writers[$0].hasFailed }
        let low = healthy.filter { freeSpace(take.folders[$0]) < reserve }
        if !low.isEmpty {
            if low.count == healthy.count {
                endedForLackOfSpace = true
                try? stopTake()
                return
            }
            for index in low {
                capture.disable(copy: index)
                writers[index].retire()
            }
        }
        if writers.count == 1, let access = driveFolder() {
            guard freeSpace(access.folder) >= reserve else { access.release(); persistGaps(); return }
            do {
                let folder = try show.joinDrive(access.folder)
                let stems = try take.stems.map { try makeStem(folder.appending(path: $0.file), take.info.described($0.description), nil) }
                try take.metadata.write(to: folder)
                let ring = capture.rings[1]
                let writer = TakeWriter(ring: ring, stems: stems, commitInterval: take.info.sampleRate * 2, onFailure: { [weak self] in
                    capture.disable(copy: 1)
                    Task { @MainActor in self?.copyFailed() }
                })
                ring.discardAll()
                ring.joinFrame.store(-1, ordering: .releasing)
                writer.start()
                capture.requestJoin(copy: 1)
                writers.append(writer)
                take.folders.append(folder)
                driveAccess = access
                currentShow = show
                self.take = take
            } catch {
                access.release()
            }
        }
        if writers.count == 2, writers[1].isFinished, writers[1].hasFailed,
           FileManager.default.fileExists(atPath: take.folders[1].path), freeSpace(take.folders[1]) >= reserve,
           let access = driveFolder() {
            do {
                let old = writers[1]
                let counts = old.stemFrameCounts
                let stems = try take.stems.enumerated().map { index, spec in
                    try makeStem(take.folders[1].appending(path: spec.file), take.info.described(spec.description), counts[index])
                }
                let ring = capture.rings[1]
                let writer = TakeWriter(ring: ring, stems: stems, commitInterval: take.info.sampleRate * 2, onFailure: { [weak self] in
                    capture.disable(copy: 1)
                    Task { @MainActor in self?.copyFailed() }
                }, priorGaps: old.gaps)
                ring.discardAll()
                ring.joinFrame.store(-1, ordering: .releasing)
                writer.start()
                capture.requestJoin(copy: 1)
                writers[1] = writer
                if driveAccess == nil { driveAccess = access } else { access.release() }
            } catch {
                access.release()
            }
        }
        persistGaps()
    }

    /// Stretches written as silence in any Copy, as `Take.json` records them.
    /// With `takeEnd`, a Copy that is still interrupted is missing everything from where it stopped to there.
    private func gaps(takeEnd: Int? = nil) -> [TakeMetadata.Gap] {
        var gaps: [TakeMetadata.Gap] = []
        for (index, writer) in writers.enumerated() {
            let copy = index == 0 ? "device" : "drive"
            for range in writer.gaps {
                gaps.append(.init(copy: copy, start: range.lowerBound, end: range.upperBound))
            }
            if let takeEnd, writer.hasFailed, writer.framesWritten < takeEnd {
                gaps.append(.init(copy: copy, start: writer.framesWritten, end: takeEnd))
            }
        }
        return gaps.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// Writes the Gaps found so far into `Take.json` in every Copy.
    private func persistGaps(takeEnd: Int? = nil) {
        guard var take else { return }
        let gaps = gaps(takeEnd: takeEnd)
        guard gaps != take.metadata.gaps else { return }
        take.metadata.gaps = gaps
        self.take = take
        for folder in take.folders { try? take.metadata.write(to: folder) }
    }

    /// A Copy's writer failed. Once every Copy has, there's nowhere left to record: end the Take.
    private func copyFailed() {
        guard isRecording, !writers.isEmpty, writers.allSatisfy(\.hasFailed) else { return }
        try? stopTake()
    }

    /// Stops the Take and waits until every Stem is written and finalized.
    /// A Copy that failed during the Take doesn't make this throw; see `copyStatus(_:)`.
    public func stopTake() throws {
        guard isRecording, let capture else { return }
        capture.stopCapturing()
        for kind in [DestinationKind.device, .drive] { finishedCopies[kind] = copyStatus(kind) }
        let writers = self.writers
        isRecording = false
        defer {
            driveAccess?.release()
            driveAccess = nil
        }
        for writer in writers { writer.stop() }
        persistGaps(takeEnd: capture.takeFrameCount)
        self.writers = []
        take = nil
        for kind in [DestinationKind.device, .drive] where finishedCopies[kind] == .recording {
            // A Copy can fail while its writer drains at stop.
            let index = kind == .device ? 0 : 1
            if writers.indices.contains(index), writers[index].hasFailed { finishedCopies[kind] = .interrupted }
        }
        // The Takes are safe either way; the report and project are regenerated next time.
        for copy in currentShow?.copies ?? [] {
            try? ShowReport.write(showFolder: copy.folder)
            try? copy.writeProjects()
        }
    }
}

/// The two places a Take is written.
public enum DestinationKind: Sendable, Hashable {
    case device, drive
}

/// How one Copy of a Take is doing.
public enum CopyStatus: Sendable, Equatable {
    case recording
    /// Its Destination failed mid-Take. The Take carries on in the other Copy.
    case interrupted
    /// It never started: no Destination.
    case missing
}

/// One Stem's file name and Source name, kept so a Copy that joins mid-Take can create the same Stems.
private struct StemSpec {
    var file: String
    var description: String
}

public enum RecorderError: Error, Equatable {
    case notArmed
}

/// Access to a Destination folder for the length of a Take. `release` ends it (for a Drive folder,
/// the security scope).
public struct DestinationAccess {
    public let folder: URL
    public let release: @MainActor () -> Void

    public init(folder: URL, release: @escaping @MainActor () -> Void = {}) {
        self.folder = folder
        self.release = release
    }
}

/// Everything the real-time callback touches, allocated when the recorder is Armed.
final class Capture: Sendable {
    let meters: PeakMeters
    /// One ring per Copy: the Device, then the Drive.
    let rings: [SampleRing]
    /// Which Copies are being captured, one bit per ring (bit 0 the Device, bit 1 the Drive); 0 when not recording.
    private let capturing = Atomic<Int>(0)
    /// Copies waiting for the real-time thread to start feeding them, one bit per ring.
    private let joinRequests = Atomic<Int>(0)
    /// Frames delivered since the Take started: the Take's sample timeline.
    private let takeFrames = Atomic<Int>(0)

    var channelCount: Int { rings[0].channelCount }

    init(channelCount: Int, sampleRate: Double) {
        meters = PeakMeters(channelCount: channelCount)
        // Four seconds of headroom for each writer thread.
        rings = (0..<2).map { _ in SampleRing(channelCount: channelCount, capacity: Int(max(sampleRate, 1) * 4)) }
    }

    func startCapturing(copies: Int) {
        takeFrames.store(0, ordering: .releasing)
        capturing.store((1 << min(copies, rings.count)) - 1, ordering: .releasing)
    }

    /// Frames delivered since the Take started.
    var takeFrameCount: Int { takeFrames.load(ordering: .acquiring) }

    /// Asks the real-time thread to start feeding one Copy's ring from its next block, and to record
    /// the Take frame it starts at in the ring's `joinFrame`.
    func requestJoin(copy: Int) {
        joinRequests.bitwiseOr(1 << copy, ordering: .acquiringAndReleasing)
    }

    /// Stops feeding one Copy's ring (its writer failed).
    func disable(copy: Int) {
        capturing.bitwiseAnd(~(1 << copy), ordering: .acquiringAndReleasing)
    }

    func stopCapturing() {
        capturing.store(0, ordering: .releasing)
    }

    /// Real-time: meter every block, and queue it for each Copy's writer while a Take is running.
    func receive(_ block: AudioBlock) {
        meters.record(block)
        let requested = joinRequests.load(ordering: .acquiring)
        if requested != 0 {
            let frame = takeFrames.load(ordering: .relaxed)
            for copy in 0..<rings.count where requested & (1 << copy) != 0 {
                rings[copy].joinFrame.store(frame, ordering: .releasing)
            }
            capturing.bitwiseOr(requested, ordering: .acquiringAndReleasing)
            joinRequests.bitwiseAnd(~requested, ordering: .acquiringAndReleasing)
        }
        let mask = capturing.load(ordering: .acquiring)
        var copy = 0
        while copy < rings.count {
            if mask & (1 << copy) != 0 { rings[copy].write(block) }
            copy += 1
        }
        takeFrames.add(block.frameCount, ordering: .relaxed)
    }
}

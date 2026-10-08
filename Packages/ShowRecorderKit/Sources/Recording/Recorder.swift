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
    /// Every Marker of the current (or last) Take, the recorder's Dropout Markers too, in the order they were
    /// placed, with their time in the Take. For the Marker list.
    public private(set) var markerEntries: [MarkerEntry] = []
    /// How much of the start of the current (or last) Take is Pre-roll, in seconds: the Marker times in the
    /// files count from before the press by this much.
    public private(set) var takePreRollSeconds: Double = 0
    /// How many stretches of audio the running (or last) Take lost because a writer couldn't keep up. Each is
    /// silence of the right length in the Stems, a Marker and an entry in `Take.json`. Updated when the
    /// recorder checks Destinations (about once a second) and when the Take ends.
    public private(set) var dropoutCount = 0
    /// The USB Channels (counted from 0) whose peak has reached full scale since they were last cleared. A
    /// clip stays marked until `clearClip(channel:)` or the next Take, so it isn't missed by looking away.
    public private(set) var clippedChannels: Set<Int> = []
    /// A peak at or above this (linear) counts as a clip: within about 0.01 dB of full scale
    /// (docs/adr/0005-level-meter-scale.md).
    public static let clipLevel: Float = 0.999
    /// Whether the last Take was ended by the recorder because the last healthy Destination was about to fill.
    public private(set) var endedForLackOfSpace = false
    /// How each Copy of the last Take ended up: complete, has Gaps, Repaired or Repair failed.
    public private(set) var lastTakeOutcomes: [DestinationKind: CopyOutcome] = [:]
    /// Whether Repair is still filling Gaps from the last Take.
    public private(set) var isRepairing = false

    /// The Device Destination: Documents/Shows.
    public static var defaultDeviceFolder: URL {
        URL.documentsDirectory.appending(path: "Shows", directoryHint: .isDirectory)
    }

    @ObservationIgnored private let deviceFolder: URL
    @ObservationIgnored private let driveFolder: () -> DestinationAccess?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let freeSpace: (URL) -> Int64
    /// How much audio before the record press a Take starts with, in seconds; 0 starts at the press. Read
    /// when record is pressed. The Armed buffer is sized from it when Arming, so a longer value than that
    /// gets what the buffer holds until the recorder is Armed again.
    @ObservationIgnored public var preRollSeconds: Double
    @ObservationIgnored private let makeStem: (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink
    @ObservationIgnored private var device: (any AudioIODevice)?
    @ObservationIgnored private var capture: Capture?
    /// The running Take's Copies.
    @ObservationIgnored private var session: TakeSession?
    @ObservationIgnored private var lastTake: LastTake?
    /// Repairs ended Takes; its result is published as `lastTakeOutcomes` and `isRepairing`.
    @ObservationIgnored private let repairQueue: RepairQueue
    @ObservationIgnored private var finishedCopies: [DestinationKind: CopyStatus] = [:]

    /// - Parameters:
    ///   - deviceFolder: where the Device Copy of every Show goes.
    ///   - driveFolder: asked at each record press for the Drive folder; nil writes to the Device only.
    public init(
        deviceFolder: URL = Recorder.defaultDeviceFolder,
        driveFolder: @escaping () -> DestinationAccess? = { nil },
        now: @escaping () -> Date = Date.init,
        freeSpace: @escaping (URL) -> Int64 = { DriveFolderStore.availableBytes(at: $0) },
        preRollSeconds: Double = 0,
        makeStem: @escaping (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink = { try StemWriter.open(url: $0, info: $1, resumingAt: $2) }
    ) {
        self.freeSpace = freeSpace
        self.preRollSeconds = preRollSeconds
        repairQueue = RepairQueue(freeSpace: freeSpace)
        self.makeStem = makeStem
        self.deviceFolder = deviceFolder
        self.driveFolder = driveFolder
        self.now = now
        repairQueue.onChange = { [unowned self] in
            lastTakeOutcomes = repairQueue.outcomes
            isRepairing = repairQueue.isRunning
        }
        repairQueue.jobDone = { [unowned self] in regenerateReports() }
    }

    /// Starts receiving audio from `device`. Any previously Armed device is stopped first.
    public func arm(_ device: any AudioIODevice) throws {
        disarm()
        let capture = Capture(channelCount: device.inputChannelCount, sampleRate: device.sampleRate, preRollSeconds: preRollSeconds)
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
        clippedChannels = []
        isArmed = false
    }

    /// Whether the Armed recorder is keeping Pre-roll audio.
    public var isKeepingPreRoll: Bool { capture?.preRoll != nil }

    /// The Pre-roll buffer of the Armed device: the last seconds of audio since Arming. Nil when not
    /// Armed or when Pre-roll is off.
    var armedPreRoll: PreRollBuffer? { capture?.preRoll }

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

    /// Each USB Channel's peak, average level and frame count since the last call. Empty when not Armed.
    public func takeChannelLevels() -> [ChannelLevel] {
        let levels = capture?.meters.takeLevels() ?? []
        for (channel, level) in levels.enumerated() where level.peak >= Self.clipLevel {
            clippedChannels.insert(channel)
        }
        if isRecording { session?.accumulate(levels) }
        return levels
    }

    /// Clears one channel's clip mark, when the operator taps it.
    public func clearClip(channel: Int) {
        clippedChannels.remove(channel)
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
        // The Take starts with up to `preRollSeconds` of what the Armed recorder has heard, so its
        // timeline, and every Stem's time reference, begin that long before the press.
        let preRollFrames = max(0, min(
            Int((preRollSeconds * device.sampleRate).rounded()),
            capture.preRoll?.totalWrittenFrames ?? 0,
            // Leave the buffer's second of margin, so the writer can't overwrite what's being read.
            (capture.preRoll?.capacity ?? 0) - Int(device.sampleRate.rounded())))
        let pressReference = UInt64(date.timeIntervalSince(Calendar.current.startOfDay(for: date)) * Double(sampleRate))
        let timeReference = pressReference >= UInt64(preRollFrames) ? pressReference - UInt64(preRollFrames) : 0
        let resolved = (0..<capture.channelCount).map { channel in
            sources.indices.contains(channel) ? sources[channel] : .fallback(usbChannel: channel + 1)
        }
        let channels = resolved.enumerated().map { index, source in
            TakeMetadata.USBChannel(usbChannel: index + 1, stemFile: StemFileName.make(usbChannel: index + 1, sourceName: source.name), source: source)
        }
        var metadata = TakeMetadata(
            show: show.name, take: show.takeCount, startedAt: date, sampleRate: sampleRate,
            timeReference: timeReference, usbChannels: channels)
        metadata.preRollFrames = preRollFrames > 0 ? preRollFrames : nil

        let specs = zip(channels, resolved).map { StemSpec(file: $0.stemFile, description: $1.name) }
        let info = StemWriter.Info(sampleRate: sampleRate, description: "", originator: "ShowRecorder", timeReference: timeReference, originationDate: date)
        let session = try TakeSession(
            show: show, folders: takeFolders, drive: takeFolders.count > 1 ? drive : nil, metadata: metadata, stems: specs,
            info: info, capture: capture, preRollFrames: preRollFrames, makeStem: makeStem, freeSpace: freeSpace)
        session.onCopyFailed = { [weak self, weak session] in self?.copyFailed(in: session) }
        if takeFolders.count == 1 { drive?.release() }
        self.session = session
        finishedCopies = [:]
        takeMarkers = []
        markerEntries = []
        dropoutCount = 0
        clippedChannels = []
        endedForLackOfSpace = false
        currentShow = show
        // The levels of a Take count from the press: drop what the meters gathered before it.
        _ = capture.meters.takeLevels()
        isRecording = true
    }

    /// Places a Marker at the Take's current sample position (frames written so far), in every Stem
    /// of every Copy and in `Take.json`. Does nothing when no Take is running.
    public func addMarker(named name: String? = nil) {
        guard isRecording, let session else { return }
        session.addMarker(named: name)
        refreshMarkers(from: session.metadata)
    }

    /// Renames one of the running Take's Markers: the one at `index` among the operator's Markers (the order
    /// of `takeMarkers`), in `Take.json` and in every Stem's cue labels, in every Copy.
    @discardableResult
    public func renameMarker(at index: Int, to name: String) -> MarkerRename {
        guard isRecording, let session else { return .notRecording }
        let result = session.renameMarker(at: index, to: name)
        refreshMarkers(from: session.metadata)
        return result
    }

    /// Where the last Take's Copies are, kept for renaming a Marker after it ended.
    private struct LastTake {
        var showName: String
        var takeNumber: Int
        var deviceFolder: URL
        var hadDrive: Bool
    }

    /// Renames one of the last Take's operator Markers (the one at `index` among them, the order of
    /// `takeMarkers`) from the files, in every Copy it can reach: `Take.json` and every Stem's cue label.
    /// The Drive is reached again for the rename and let go after. The outcome names any Copy that wasn't
    /// updated. Waits for Repair first, which would otherwise write the old name back.
    public func renameLastTakeMarker(at index: Int, to name: String) async -> MarkerRenamer.Outcome {
        await repairQueue.wait()
        guard !isRecording, let take = lastTake else { return MarkerRenamer.Outcome(result: .notRecording, renamed: [], failed: []) }
        var copies: [DestinationKind: URL] = [.device: take.deviceFolder]
        var access: DestinationAccess?
        if take.hadDrive {
            access = driveFolder()
            if let access { copies[.drive] = access.folder.appending(path: take.showName).appending(path: String(format: "Take %02d", take.takeNumber)) }
        }
        defer { access?.release() }
        var outcome = MarkerRenamer.rename(markerAt: index, to: name, in: copies)
        if take.hadDrive, access == nil {
            outcome.failed.append(.init(copy: .drive, reason: "The Drive isn't available, so its Copy still has the old name."))
        }
        if !outcome.renamed.isEmpty, let metadata = Self.readTake(at: take.deviceFolder) { refreshMarkers(from: metadata) }
        return outcome
    }

    private static func readTake(at folder: URL) -> TakeMetadata? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: folder.appending(path: TakeMetadata.fileName))).flatMap { try? decoder.decode(TakeMetadata.self, from: $0) }
    }

    /// Updates `takeMarkers` and `markerEntries` from the Take's metadata.
    private func refreshMarkers(from metadata: TakeMetadata) {
        takeMarkers = metadata.markers.filter { $0.origin == .operator }
        let preRoll = metadata.sampleRate > 0 ? Double(metadata.preRollFrames ?? 0) / Double(metadata.sampleRate) : 0
        takePreRollSeconds = preRoll
        var operatorIndex = 0
        markerEntries = metadata.markers.enumerated().map { place, marker in
            defer { if marker.origin == .operator { operatorIndex += 1 } }
            return MarkerEntry(
                id: place,
                operatorIndex: marker.origin == .operator ? operatorIndex : nil,
                seconds: metadata.sampleRate > 0 ? Double(marker.position) / Double(metadata.sampleRate) : 0,
                secondsSincePress: metadata.sampleRate > 0
                    ? Double(max(marker.position - (metadata.preRollFrames ?? 0), 0)) / Double(metadata.sampleRate) : 0,
                name: marker.name)
        }
    }

    /// How `kind`'s Copy of the current (or last) Take is doing. A Copy that never started is missing.
    public func copyStatus(_ kind: DestinationKind) -> CopyStatus {
        guard isRecording, let session else { return finishedCopies[kind] ?? .missing }
        return session.status(kind)
    }

    /// Looks for a Destination that has become available since the Take started. A Drive that appears
    /// joins the running Take: its Stems start with silence up to the join point, which is recorded as
    /// a Gap in `Take.json` on both Copies. Call it regularly while recording.
    public func checkDestinations() {
        guard isRecording, let session else { return }
        switch session.checkDestinations(drive: driveFolder) {
        case .carryOn:
            currentShow = session.show
            dropoutCount = session.dropoutCount
            refreshMarkers(from: session.metadata)
        case .outOfSpace:
            endedForLackOfSpace = true
            try? stopTake()
        }
    }

    /// A Copy's writer failed. Once every Copy has, there's nowhere left to record: end the Take.
    private func copyFailed(in failed: TakeSession?) {
        guard isRecording, let session, session === failed, session.allFailed else { return }
        try? stopTake()
    }

    /// Stops the Take and waits until every Stem is written and finalized.
    /// A Copy that failed during the Take doesn't make this throw; see `copyStatus(_:)`.
    public func stopTake() throws {
        guard isRecording, let session else { return }
        // Not recording from here on, so a Copy that fails while draining doesn't stop the Take again.
        isRecording = false
        self.session = nil
        // The last window, which the screen hasn't read yet, is still part of the Take.
        session.accumulate(capture?.meters.takeLevels() ?? [])
        let finished = session.finish()
        finishedCopies = finished.statuses
        dropoutCount = finished.metadata.markers.filter { $0.origin == .dropout }.count
        refreshMarkers(from: finished.metadata)
        lastTake = LastTake(
            showName: session.show.name, takeNumber: finished.metadata.take, deviceFolder: finished.folders[0],
            hadDrive: finished.folders.count > 1)
        currentShow = session.show
        // The Takes are safe either way; the report and project are regenerated next time.
        regenerateReports()
        repairQueue.enqueue(finished.metadata, folders: finished.folders, holding: finished.access)
    }

    private func regenerateReports() {
        for copy in currentShow?.copies ?? [] {
            try? ShowReport.write(showFolder: copy.folder)
            try? copy.writeProjects()
        }
    }

    /// Waits for Repair of the last Take to finish.
    public func waitForRepair() async {
        await repairQueue.wait()
    }
}

/// How one Copy of a Take is doing.
public enum CopyStatus: Sendable, Equatable {
    case recording
    /// Its Destination failed mid-Take. The Take carries on in the other Copy.
    case interrupted
    /// It never started: no Destination.
    case missing
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
    /// The last seconds of every channel while Armed, for Pre-roll. Nil when Pre-roll is off.
    let preRoll: PreRollBuffer?
    /// One ring per Copy: the Device, then the Drive.
    let rings: [SampleRing]
    /// Which Copies are being captured, one bit per ring (bit 0 the Device, bit 1 the Drive); 0 when not recording.
    private let capturing = Atomic<Int>(0)
    /// Copies waiting for the real-time thread to start feeding them, one bit per ring.
    private let joinRequests = Atomic<Int>(0)
    /// Frames delivered since the Take started: the Take's sample timeline. A Take with Pre-roll starts
    /// it at the Pre-roll's length, so frame 0 is the first Pre-roll sample.
    private let takeFrames = Atomic<Int>(0)
    /// For a Take with Pre-roll: where the Take's first live frame sits in the Pre-roll buffer's own count,
    /// set by the real-time thread at the block that starts feeding the Copies. -2 until then, -1 when the
    /// Take has no Pre-roll.
    let preRollStart = Atomic<Int>(-1)

    var channelCount: Int { rings[0].channelCount }

    /// - Parameter preRollSeconds: how much audio to keep before a Take starts; the buffer holds a second
    ///   more, so a snapshot of that length isn't cut short by the writer overwriting its oldest frames.
    init(channelCount: Int, sampleRate: Double, preRollSeconds: Double = 0) {
        meters = PeakMeters(channelCount: channelCount)
        preRoll = preRollSeconds > 0
            ? PreRollBuffer(channelCount: channelCount, capacity: Int((preRollSeconds + 1) * max(sampleRate, 1)))
            : nil
        // Four seconds of headroom for each writer thread.
        rings = (0..<2).map { _ in SampleRing(channelCount: channelCount, capacity: Int(max(sampleRate, 1) * 4)) }
    }

    /// Starts feeding the Copies' rings. With `preRollFrames`, the Take's timeline starts at that many
    /// frames and the Copies start at the next block boundary, which the real-time thread notes in
    /// `preRollStart` so the Pre-roll and the live audio join without a lost or repeated sample.
    func startCapturing(copies: Int, preRollFrames: Int = 0) {
        let mask = (1 << min(copies, rings.count)) - 1
        takeFrames.store(preRollFrames, ordering: .releasing)
        if preRollFrames > 0, preRoll != nil {
            preRollStart.store(-2, ordering: .releasing)
            joinRequests.store(mask, ordering: .releasing)
        } else {
            preRollStart.store(-1, ordering: .releasing)
            capturing.store(mask, ordering: .releasing)
        }
    }

    /// Whether the Take has Pre-roll but the real-time thread hasn't yet fed it a first block.
    var awaitingFirstBlock: Bool { preRollStart.load(ordering: .acquiring) == -2 }

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
        preRoll?.write(block)
        let requested = joinRequests.load(ordering: .acquiring)
        if requested != 0 {
            let frame = takeFrames.load(ordering: .relaxed)
            if preRollStart.load(ordering: .relaxed) == -2 {
                // The Pre-roll buffer already holds this block, so the live audio starts before it.
                preRollStart.store((preRoll?.totalWrittenFrames ?? block.frameCount) - block.frameCount, ordering: .releasing)
            }
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
        if mask != 0 { takeFrames.add(block.frameCount, ordering: .relaxed) }
    }
}

/// One line of the Marker list: a Marker with its time in the Take (counted from the start of the audio,
/// as in the Stems, the report and the project).
public struct MarkerEntry: Equatable, Identifiable, Sendable {
    /// Its place in the Take's list of all Markers.
    public var id: Int
    /// Which operator Marker this is (the index `Recorder.renameMarker` takes), or nil for a Dropout Marker,
    /// which the recorder placed and which can't be renamed.
    public var operatorIndex: Int?
    /// Counted from the start of the audio, which includes the Pre-roll.
    public var seconds: Double
    /// Counted from when Record was pressed, as the timer on the record screen does.
    public var secondsSincePress: Double
    public var name: String

    public var isDropout: Bool { operatorIndex == nil }
}

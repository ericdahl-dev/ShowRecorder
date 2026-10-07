import AudioIO
import BroadcastWave
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

    /// The Device Destination: Documents/Shows.
    public static var defaultDeviceFolder: URL {
        URL.documentsDirectory.appending(path: "Shows", directoryHint: .isDirectory)
    }

    @ObservationIgnored private let deviceFolder: URL
    @ObservationIgnored private let driveFolder: () -> DestinationAccess?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var device: (any AudioIODevice)?
    @ObservationIgnored private var capture: Capture?
    @ObservationIgnored private var writers: [TakeWriter] = []
    @ObservationIgnored private var driveAccess: DestinationAccess?

    /// - Parameters:
    ///   - deviceFolder: where the Device Copy of every Show goes.
    ///   - driveFolder: asked at each record press for the Drive folder; nil writes to the Device only.
    public init(
        deviceFolder: URL = Recorder.defaultDeviceFolder,
        driveFolder: @escaping () -> DestinationAccess? = { nil },
        now: @escaping () -> Date = Date.init
    ) {
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
        var writers: [TakeWriter] = []
        for (copy, takeFolder) in takeFolders.enumerated() {
            let stems = try zip(channels, resolved).map { channel, source in
                try StemWriter(
                    url: takeFolder.appending(path: channel.stemFile),
                    info: .init(sampleRate: sampleRate, description: source.name, originator: "ShowRecorder", timeReference: timeReference, originationDate: date))
            }
            try metadata.write(to: takeFolder)
            writers.append(TakeWriter(ring: capture.rings[copy], stems: stems, commitInterval: sampleRate * 2))
        }

        for (copy, writer) in writers.enumerated() {
            capture.rings[copy].discardAll()
            writer.start()
        }
        capture.startCapturing(copies: writers.count)

        self.writers = writers
        driveAccess = takeFolders.count > 1 ? drive : nil
        if takeFolders.count == 1 { drive?.release() }
        currentShow = show
        isRecording = true
    }

    /// Stops the Take and waits until every Stem is written and finalized.
    public func stopTake() throws {
        guard isRecording, let capture else { return }
        capture.stopCapturing()
        let writers = self.writers
        self.writers = []
        isRecording = false
        defer {
            driveAccess?.release()
            driveAccess = nil
        }
        var firstError: (any Error)?
        for writer in writers {
            do { try writer.stop() } catch { firstError = firstError ?? error }
        }
        // The Takes are safe either way; the report and project are regenerated next time.
        for copy in currentShow?.copies ?? [] {
            try? ShowReport.write(showFolder: copy.folder)
            try? copy.writeProjects()
        }
        if let firstError { throw firstError }
    }
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
    /// How many Copies are being captured: 0 (not recording), 1 (Device) or 2 (Device and Drive).
    private let capturing = Atomic<Int>(0)

    var channelCount: Int { rings[0].channelCount }

    init(channelCount: Int, sampleRate: Double) {
        meters = PeakMeters(channelCount: channelCount)
        // Four seconds of headroom for each writer thread.
        rings = (0..<2).map { _ in SampleRing(channelCount: channelCount, capacity: Int(max(sampleRate, 1) * 4)) }
    }

    func startCapturing(copies: Int) {
        capturing.store(min(copies, rings.count), ordering: .releasing)
    }

    func stopCapturing() {
        capturing.store(0, ordering: .releasing)
    }

    /// Real-time: meter every block, and queue it for each Copy's writer while a Take is running.
    func receive(_ block: AudioBlock) {
        meters.record(block)
        let copies = capturing.load(ordering: .acquiring)
        var copy = 0
        while copy < copies {
            rings[copy].write(block)
            copy += 1
        }
    }
}

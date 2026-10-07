import AudioIO
import BroadcastWave
import Foundation
import MixerLink
import Observation
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

    /// The XR18 and MR18 send 18 USB Channels. Fewer means some of the Mixer won't be recorded.
    public static let expectedUSBChannelCount = 18

    /// The Device Destination: Documents/Shows.
    public static var defaultDeviceFolder: URL {
        URL.documentsDirectory.appending(path: "Shows", directoryHint: .isDirectory)
    }

    /// True while Armed on a device with fewer than 18 USB Channels.
    public var hasTooFewUSBChannels: Bool {
        isArmed && usbChannelCount < Self.expectedUSBChannelCount
    }

    @ObservationIgnored private let deviceFolder: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var device: (any AudioIODevice)?
    @ObservationIgnored private var capture: Capture?
    @ObservationIgnored private var writer: TakeWriter?

    public init(deviceFolder: URL = Recorder.defaultDeviceFolder, now: @escaping () -> Date = Date.init) {
        self.deviceFolder = deviceFolder
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
        capture?.ring.overflowedFrames.load(ordering: .relaxed) ?? 0
    }

    /// Frames captured but not yet written to the Stems.
    var bufferedFrameCount: Int {
        capture?.ring.availableFrames ?? 0
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

        var show = try currentShow ?? Show.create(in: deviceFolder, on: date)
        let takeFolder = try show.createNextTakeFolder()

        let sampleRate = Int(device.sampleRate.rounded())
        let timeReference = UInt64(date.timeIntervalSince(Calendar.current.startOfDay(for: date)) * Double(sampleRate))
        var channels: [TakeMetadata.USBChannel] = []
        let stems = try (0..<capture.ring.channelCount).map { channel in
            let source = sources.indices.contains(channel) ? sources[channel] : .fallback(usbChannel: channel + 1)
            let fileName = StemFileName.make(usbChannel: channel + 1, sourceName: source.name)
            channels.append(TakeMetadata.USBChannel(usbChannel: channel + 1, stemFile: fileName, source: source))
            return try StemWriter(
                url: takeFolder.appending(path: fileName),
                info: .init(sampleRate: sampleRate, description: source.name, originator: "ShowRecorder", timeReference: timeReference, originationDate: date))
        }
        try TakeMetadata(
            show: show.name, take: show.takeCount, startedAt: date, sampleRate: sampleRate,
            timeReference: timeReference, usbChannels: channels
        ).write(to: takeFolder)

        let writer = TakeWriter(ring: capture.ring, stems: stems, commitInterval: sampleRate * 2)
        capture.ring.discardAll()
        writer.start()
        capture.isCapturing.store(true, ordering: .releasing)

        self.writer = writer
        currentShow = show
        isRecording = true
    }

    /// Stops the Take and waits until every Stem is written and finalized.
    public func stopTake() throws {
        guard isRecording, let capture, let writer else { return }
        capture.isCapturing.store(false, ordering: .releasing)
        self.writer = nil
        isRecording = false
        try writer.stop()
    }
}

public enum RecorderError: Error, Equatable {
    case notArmed
}

/// Everything the real-time callback touches, allocated when the recorder is Armed.
final class Capture: Sendable {
    let meters: PeakMeters
    let ring: SampleRing
    let isCapturing = Atomic<Bool>(false)

    init(channelCount: Int, sampleRate: Double) {
        meters = PeakMeters(channelCount: channelCount)
        // Four seconds of headroom for the writer thread.
        ring = SampleRing(channelCount: channelCount, capacity: Int(max(sampleRate, 1) * 4))
    }

    /// Real-time: meter every block, and queue it for the writer while a Take is running.
    func receive(_ block: AudioBlock) {
        meters.record(block)
        if isCapturing.load(ordering: .acquiring) {
            ring.write(block)
        }
    }
}

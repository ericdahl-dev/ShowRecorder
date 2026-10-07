import AudioIO
import BroadcastWave
import Foundation
@testable import Recording
import Testing

/// A Stem that fails every append after `healthyFrames`, standing in for a Destination that went away.
final class FailingStem: StemSink, @unchecked Sendable {
    struct Failure: Error {}
    private let real: StemWriter
    private let healthyFrames: Int
    private var frames = 0
    var frameCount: UInt64 { real.frameCount }

    init(_ real: StemWriter, healthyFrames: Int) {
        self.real = real
        self.healthyFrames = healthyFrames
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws {
        if frames + samples.count > healthyFrames { throw Failure() }
        frames += samples.count
        try real.append(samples)
    }
    func commitHeader() throws { try real.commitHeader() }
    func finalize() throws { try real.finalize() }
    @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try real.setMarkers(markers) }
}

@MainActor
@Suite("Gaps")
struct GapTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "GapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    /// A recorder whose Copy on each named Destination fails after `healthyFrames`.
    func recorder(failing failing: Set<DestinationKind>, healthyFrames: Int = 480) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { DestinationAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info in
                let real = try StemWriter(url: url, info: info)
                let kind: DestinationKind = url.path.contains("/Drive/") ? .drive : .device
                return failing.contains(kind) ? FailingStem(real, healthyFrames: healthyFrames) : real
            })
    }

    func deliverBlocks(_ count: Int, to audio: FakeAudioDevice, _ recorder: Recorder) async throws {
        for block in 0..<count {
            audio.deliver([(0..<480).map { RecordingTakeTests.sample(Int32(block * 480 + $0)) }])
            try await waitUntil { recorder.bufferedFrameCount == 0 }
        }
    }

    @Test("A Device that fails mid-Take is marked interrupted and the Drive Copy carries on")
    func deviceFailsMidTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.device])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder)
        try await waitUntil { recorder.copyStatus(.device) == .interrupted }

        #expect(recorder.copyStatus(.device) == .interrupted)
        #expect(recorder.copyStatus(.drive) == .recording)
        try recorder.stopTake()

        let driveStem = try StemFile(contentsOf: drive.appending(path: "2026-10-06 Show/Take 01/01 USB 01.wav"))
        #expect(driveStem.samples.count == 4800)
    }

    @Test("When every Copy has failed the Take ends on its own")
    func takeEndsWhenEveryCopyFailed() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.device, .drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder)
        try await waitUntil { !recorder.isRecording }

        #expect(!recorder.isRecording)
        #expect(recorder.copyStatus(.device) == .interrupted)
        #expect(recorder.copyStatus(.drive) == .interrupted)
    }

    @Test("A Drive that fails mid-Take is marked interrupted and the Device Copy carries on")
    func driveFailsMidTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { DestinationAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info in
                let real = try StemWriter(url: url, info: info)
                return url.path.hasPrefix(drive.resolvingSymlinksInPath().path) || url.path.hasPrefix(drive.path)
                    ? FailingStem(real, healthyFrames: 480) : real
            })
        try recorder.arm(audio)

        try recorder.startTake()
        for block in 0..<10 {
            audio.deliver([(0..<480).map { RecordingTakeTests.sample(Int32(block * 480 + $0)) }])
            try await waitUntil { recorder.bufferedFrameCount == 0 }
        }
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }

        #expect(recorder.copyStatus(.device) == .recording)
        #expect(recorder.copyStatus(.drive) == .interrupted)
        try recorder.stopTake()

        let deviceStem = try StemFile(contentsOf: device.appending(path: "2026-10-06 Show/Take 01/01 USB 01.wav"))
        #expect(deviceStem.samples.count == 4800)
    }

    @Test("With no Drive at record the Take starts on the Device and the Drive Copy is missing")
    func noDriveAtStartIsMissing() throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)

        try recorder.startTake()

        #expect(recorder.isRecording)
        #expect(recorder.copyStatus(.device) == .recording)
        #expect(recorder.copyStatus(.drive) == .missing)
        try recorder.stopTake()
        #expect(recorder.copyStatus(.drive) == .missing)
    }

    @Test("A Drive that appears mid-Take joins with the missed span written as silence and recorded as a Gap")
    func driveJoinsMidTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let available = DriveSwitch()
        let recorder = Recorder(deviceFolder: device, driveFolder: { available.folder.map { DestinationAccess(folder: $0) } }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder)
        available.folder = drive
        recorder.checkDestinations()
        #expect(recorder.copyStatus(.drive) == .recording)
        for block in 10..<15 {
            audio.deliver([(0..<480).map { RecordingTakeTests.sample(Int32(block * 480 + $0)) }])
            try await waitUntil { recorder.bufferedFrameCount == 0 }
        }
        try recorder.stopTake()

        let take = "2026-10-06 Show/Take 01"
        let deviceStem = try StemFile(contentsOf: device.appending(path: "\(take)/01 USB 01.wav"))
        let driveStem = try StemFile(contentsOf: drive.appending(path: "\(take)/01 USB 01.wav"))
        #expect(deviceStem.samples.count == 7200)
        #expect(driveStem.samples.count == 7200)
        #expect(driveStem.samples[..<4800].allSatisfy { $0 == 0 })
        #expect(Array(driveStem.samples[4800...]) == Array(deviceStem.samples[4800...]))

        let expected = [TakeMetadata.Gap(copy: "drive", start: 0, end: 4800)]
        for folder in [device, drive] {
            let json = try Data(contentsOf: folder.appending(path: "\(take)/Take.json"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            #expect(try decoder.decode(TakeMetadata.self, from: json).gaps == expected)
        }
    }
}

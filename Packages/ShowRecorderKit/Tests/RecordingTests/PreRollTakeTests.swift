import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

/// A Take begins with the audio from before record was pressed.
@MainActor
@Suite("Pre-roll in the Take")
struct PreRollTakeTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "PreRollTakeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// Delivers the ramp `start..<start+count` (each sample is its own index) to `audio`, waiting for the
    /// writers to keep up when a Take is running.
    func deliver(_ count: Int, from start: Int, to audio: FakeAudioDevice, _ recorder: Recorder, block: Int = 480) async throws {
        var frame = start
        while frame < start + count {
            let n = min(block, start + count - frame)
            audio.deliver((0..<audio.inputChannelCount).map { channel in
                (0..<n).map { RecordingTakeTests.sample(Int32(frame + $0 + channel * 1_000_000)) }
            })
            frame += n
            if recorder.isRecording { try await waitUntil { recorder.bufferedFrameCount == 0 } }
        }
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    func take01(_ copy: URL) -> URL { copy.appending(path: "2026-10-06 Show/Take 01") }

    func decodedTake(_ copy: URL) throws -> TakeMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: Data(contentsOf: take01(copy).appending(path: "Take.json")))
    }

    func recorder(seconds: Double, drive available: Box<Bool>? = nil) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { available?.value == true ? DestinationAccess(folder: drive) : nil },
            now: { RecordingTakeTests.showDay }, preRollSeconds: seconds)
    }

    final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    @Test("A Take begins with the last N seconds from before record was pressed, then the live audio, sample for sample")
    func takeStartsWithPreRoll() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let recorder = recorder(seconds: 1)
        try recorder.arm(audio)
        try await deliver(144_000, from: 0, to: audio, recorder)  // 3 s while Armed

        try recorder.startTake()
        try await deliver(1_000, from: 144_000, to: audio, recorder)
        try recorder.stopTake()

        for (index, name) in ["01 USB 01.wav", "02 USB 02.wav"].enumerated() {
            let stem = try StemFile(contentsOf: take01(device).appending(path: name))
            #expect(stem.samples == (96_000..<145_000).map { Int32($0 + index * 1_000_000) }, "\(name)")
        }
    }

    @Test("Armed for less than N seconds, the Take starts with what there is, with no silence added")
    func shortPreRoll() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(seconds: 1)
        try recorder.arm(audio)
        try await deliver(24_000, from: 0, to: audio, recorder)

        try recorder.startTake()
        try await deliver(1_000, from: 24_000, to: audio, recorder)
        try recorder.stopTake()

        let stem = try StemFile(contentsOf: take01(device).appending(path: "01 USB 01.wav"))
        #expect(stem.samples == (0..<25_000).map { Int32($0) })
    }

    @Test("With Pre-roll off the Take starts at the press")
    func off() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(seconds: 0)
        try recorder.arm(audio)
        try await deliver(24_000, from: 0, to: audio, recorder)
        try recorder.startTake()
        try await deliver(1_000, from: 24_000, to: audio, recorder)
        try recorder.stopTake()

        let stem = try StemFile(contentsOf: take01(device).appending(path: "01 USB 01.wav"))
        #expect(stem.samples == (24_000..<25_000).map { Int32($0) })
        #expect(try decodedTake(device).preRollFrames == nil)
    }

    @Test("The time reference is the start of the Pre-roll, in every Stem and in Take.json")
    func timeReference() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let recorder = recorder(seconds: 1)
        try recorder.arm(audio)
        try await deliver(96_000, from: 0, to: audio, recorder)
        try recorder.startTake()
        try await deliver(480, from: 96_000, to: audio, recorder)
        try recorder.stopTake()

        // 21:30:00 is 77,400 s after midnight; the Pre-roll is the 48,000 frames before it.
        let atPress: UInt64 = 77_400 * 48_000
        let take = try decodedTake(device)
        #expect(take.timeReference == atPress - 48_000)
        #expect(take.preRollFrames == 48_000)
        for name in ["01 USB 01.wav", "02 USB 02.wav"] {
            #expect(try StemFile(contentsOf: take01(device).appending(path: name)).timeReference == atPress - 48_000)
        }
    }

    @Test("A Marker placed after the press is at its place on the timeline that starts with the Pre-roll")
    func markerPosition() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(seconds: 1)
        try recorder.arm(audio)
        try await deliver(48_000, from: 0, to: audio, recorder)
        try recorder.startTake()
        try await deliver(960, from: 48_000, to: audio, recorder)
        recorder.addMarker()
        try await deliver(480, from: 48_960, to: audio, recorder)
        try recorder.stopTake()

        #expect(recorder.takeMarkers.map(\.position) == [48_000 + 960])
    }

    @Test("A Drive that joins mid-Take is missing the Pre-roll as a Gap, and Repair fills it from the Device")
    func lateDriveGetsPreRollByRepair() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let available = Box(false)
        let recorder = recorder(seconds: 1, drive: available)
        try recorder.arm(audio)
        try await deliver(48_000, from: 0, to: audio, recorder)
        try recorder.startTake()
        try await deliver(2_400, from: 48_000, to: audio, recorder)

        available.value = true
        recorder.checkDestinations()
        try await deliver(2_400, from: 50_400, to: audio, recorder)
        try recorder.stopTake()
        await recorder.waitForRepair()

        let deviceStem = try Data(contentsOf: take01(device).appending(path: "01 USB 01.wav"))
        let driveStem = try Data(contentsOf: take01(drive).appending(path: "01 USB 01.wav"))
        #expect(deviceStem == driveStem)
        let samples = try StemFile(contentsOf: take01(drive).appending(path: "01 USB 01.wav")).samples
        #expect(samples == (0..<52_800).map { Int32($0) })
        #expect(try decodedTake(device).gaps.first?.start == 0)
    }

    @Test("Pressing record and stopping before any audio arrives leaves an empty Take with no Gap")
    func stopBeforeAnyBlock() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(seconds: 1)
        try recorder.arm(audio)
        try await deliver(48_000, from: 0, to: audio, recorder)
        try recorder.startTake()
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(try decodedTake(device).gaps.isEmpty)
    }
}

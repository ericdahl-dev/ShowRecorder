import AudioIO
import BroadcastWave
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Audio lost while input was stopped (a call, Siri, another app) is silence with a Dropout, so the Stems keep
/// their length and stay in sync with video (#317).
@MainActor
@Suite("Interruption Dropout")
struct InterruptionDropoutTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "InterruptionDropoutTests-\(UUID().uuidString)")
    let show = "2026-10-06 Show"

    @Test("Input that stops for a second mid-Take leaves a second of silence and a Dropout where it was")
    func gapBecomesDropout() async throws {
        // One host-clock tick per frame at 48 kHz, so the test can say exactly how long input stopped.
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil, hostTicksPerSecond: 48_000)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_000)
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_480)
        // Input stops here for 48,000 frames (1 s), then comes back.
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_960 + 48_000)
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_960 + 48_480)
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try await recorder.stopTake()
        await recorder.waitForRepair()

        let take = root.appending(path: "\(show)/Take 01")
        let stem = try ParsedStem(contentsOf: take.appending(path: "01 USB 01.wav"))
        #expect(stem.samples.count == 4 * 480 + 48_000)
        #expect(stem.samples[960..<(960 + 48_000)].allSatisfy { $0 == 0 }, "the stopped second is silence")
        #expect(stem.samples[(960 + 48_000)...].allSatisfy { $0 != 0 }, "the audio after it is where it belongs")
        let metadata = try TakeMetadata.read(fromTakeFolder: take)
        #expect(metadata.dropouts == [TakeMetadata.Dropout(copy: .device, start: 960, end: 960 + 48_000)])
        #expect(metadata.markers.contains { $0.origin == .dropout && $0.position == 960 })
    }

    @Test("A Take pressed while input is stopped is silent from the press, not from when input stopped (#877)")
    func pressWhileStopped() async throws {
        // Input stops at host time 1_960; record is pressed 1 s later, and input comes back 1 s after the press.
        let press: UInt64 = 1_960 + 48_000
        let recorder = Recorder(
            deviceFolder: root, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil, hostTicksPerSecond: 48_000,
            hostClock: { press })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_000)
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_480)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: press + 48_000)
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: press + 48_480)
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try await recorder.stopTake()
        await recorder.waitForRepair()

        let take = root.appending(path: "\(show)/Take 01")
        let stem = try ParsedStem(contentsOf: take.appending(path: "01 USB 01.wav"))
        #expect(stem.samples.count == 48_000 + 2 * 480, "the second from the press to input's return, then the audio")
        #expect(stem.samples[..<48_000].allSatisfy { $0 == 0 })
        #expect(stem.samples[48_000...].allSatisfy { $0 != 0 })
        let metadata = try TakeMetadata.read(fromTakeFolder: take)
        #expect(metadata.dropouts == [TakeMetadata.Dropout(copy: .device, start: 0, end: 48_000)])
    }

    @Test("With Pre-roll, a Take pressed while input is stopped has the Pre-roll, silence from the press, then the audio (#877)")
    func pressWhileStoppedWithPreRoll() async throws {
        // 1 s Armed (host times 1_000 to 49_000), input stops, record 1 s later, input back 1 s after the press.
        let press: UInt64 = 49_000 + 48_000
        let recorder = Recorder(
            deviceFolder: root, now: { RecordingTakeTests.showDay }, preRollSeconds: 1, destinationCheckInterval: nil,
            hostTicksPerSecond: 48_000, hostClock: { press })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        for block in 0..<100 { audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_000 + UInt64(block * 480)) }
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: press + 48_000)
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: press + 48_480)
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try await recorder.stopTake()
        await recorder.waitForRepair()

        let take = root.appending(path: "\(show)/Take 01")
        let stem = try ParsedStem(contentsOf: take.appending(path: "01 USB 01.wav"))
        #expect(stem.samples.count == 96_960, "1 s of Pre-roll, 1 s of silence, 960 frames of audio")
        #expect(stem.samples[..<48_000].allSatisfy { $0 != 0 }, "the Pre-roll")
        #expect(stem.samples[48_000..<96_000].allSatisfy { $0 == 0 }, "the press to input's return")
        #expect(stem.samples[96_000...].allSatisfy { $0 != 0 }, "the audio after it")
        let metadata = try TakeMetadata.read(fromTakeFolder: take)
        #expect(metadata.preRollFrames == 48_000)
        #expect(metadata.dropouts == [TakeMetadata.Dropout(copy: .device, start: 48_000, end: 96_000)])
    }

    @Test("Ordinary timing jitter between blocks is not a Dropout")
    func jitterIsNotADropout() async throws {
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil, hostTicksPerSecond: 48_000)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_000)
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_000 + 480 + 30)  // 30 frames late
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try await recorder.stopTake()
        let metadata = try TakeMetadata.read(fromTakeFolder: root.appending(path: "\(show)/Take 01"))
        #expect(metadata.dropouts.isEmpty)
    }
}

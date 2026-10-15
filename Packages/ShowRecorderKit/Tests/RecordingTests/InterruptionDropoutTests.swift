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
        try recorder.stopTake()
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

    @Test("Ordinary timing jitter between blocks is not a Dropout")
    func jitterIsNotADropout() async throws {
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil, hostTicksPerSecond: 48_000)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_000)
        audio.deliver([Array(repeating: 0.5, count: 480)], hostTime: 1_000 + 480 + 30)  // 30 frames late
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try recorder.stopTake()
        let metadata = try TakeMetadata.read(fromTakeFolder: root.appending(path: "\(show)/Take 01"))
        #expect(metadata.dropouts.isEmpty)
    }
}

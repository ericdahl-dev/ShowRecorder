import AudioIO
import Foundation
@testable import Recording
import Testing

/// The headphone monitor experiment (#233) must not change a Take: the same input recorded through the monitor's tap
/// gives byte-identical Stems.
@MainActor
@Suite("Monitor tap and Stems")
struct MonitorTapStemTests {
    /// Records 2 channels of a fixed signal through `wrap(device)` and returns each Stem's bytes, by file name.
    func record(wrap: (FakeAudioDevice) -> any AudioIODevice) async throws -> [String: Data] {
        let root = FileManager.default.temporaryDirectory.appending(path: "MonitorTapStemTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(wrap(device))
        try recorder.startTake()
        try await deliver(9_600, to: device, recorder) { frame, channel in Float(frame % 97) / 97 - Float(channel) * 0.5 }
        try await recorder.stopTake()
        await recorder.waitForRepair()
        let take = root.appending(path: "2026-10-06 Show/Take 01")
        let stems = try FileManager.default.contentsOfDirectory(atPath: take.path).filter { $0.hasSuffix(".wav") }.sorted()
        return try Dictionary(uniqueKeysWithValues: stems.map { ($0, try Data(contentsOf: take.appending(path: $0))) })
    }

    @Test("A Take recorded through the monitor's tap has byte-identical Stems to one recorded without it")
    func stemsIdentical() async throws {
        let plain = try await record { $0 }
        let ring = MonitorRing(capacity: 16_384)
        let tapped = try await record { MonitorTap($0, ring: ring) }
        #expect(plain.count == 2)
        #expect(tapped == plain)
        #expect(ring.availableFrames > 0, "the monitor got the audio too")
    }
}

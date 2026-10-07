import AudioIO
import Foundation
@testable import Recording
import Testing

@MainActor
@Suite("Full session")
struct FullSessionTests {
    @Test("18 USB Channels of a long deterministic signal decode back sample-accurately and aligned")
    func eighteenChannelsDecodeExactly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FullSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let device = FakeAudioDevice(inputChannelCount: 18)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)

        // 6 seconds in 512-frame blocks: longer than the 4-second ring, so it wraps.
        let blockFrames = 512
        let blocks = 48_000 * 6 / blockFrames
        /// Sample `frame` of channel `c` is `c × 400 000 + frame`, unique and exact in 24 bits.
        func value(_ channel: Int, _ frame: Int) -> Int32 { Int32(channel * 400_000 + frame) }

        try recorder.startTake()
        for block in 0..<blocks {
            let channels = (0..<18).map { channel in
                (0..<blockFrames).map { Float(value(channel, block * blockFrames + $0)) / 8_388_608 }
            }
            device.deliver(channels)
            // Let the writer catch up before the ring could fill (the fake runs faster than real time).
            while recorder.bufferedFrameCount > 48_000 * 2 {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        try recorder.stopTake()

        let take = root.appending(path: "2026-10-06 Show/Take 01")
        let total = blocks * blockFrames
        for channel in 0..<18 {
            let number = String(format: "%02d", channel + 1)
            let stem = try StemFile(contentsOf: take.appending(path: "\(number) USB \(number).wav"))
            #expect(stem.samples.count == total, "channel \(channel + 1) length")
            #expect(stem.samples == (0..<total).map { value(channel, $0) }, "channel \(channel + 1) content")
        }
        #expect(recorder.droppedFrameCount == 0)
    }
}

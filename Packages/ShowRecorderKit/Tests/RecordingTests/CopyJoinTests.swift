import AudioIO
import Foundation
@testable import Recording
import Testing

/// How a Copy joins the Take on the real-time side, and what its writer makes of the join (#85). Synchronous: each
/// test hands Capture its blocks itself.
@Suite("Copy join")
struct CopyJoinTests {
    /// Host-clock ticks run at the sample rate, so a block's host time is counted in frames.
    func capture(preRollSeconds: Double = 0) -> Capture {
        Capture(channelCount: 1, sampleRate: 48_000, preRollSeconds: preRollSeconds, hostTicksPerSecond: 48_000)
    }

    func receive(_ capture: Capture, frames: Int = 480, at hostTime: UInt64 = 0) {
        var samples = [Float](repeating: 0.25, count: frames)
        samples.withUnsafeMutableBufferPointer { buffer in
            var pointer = UnsafePointer(buffer.baseAddress!)
            withUnsafePointer(to: &pointer) {
                capture.receive(AudioBlock(channels: $0, channelCount: 1, frameCount: frames, hostTime: hostTime))
            }
        }
    }

    @Test("A Copy asked to join starts at the next block: its join frame is the Take frame before that block, and only it changes")
    func joinAtNextBlock() {
        let capture = capture()
        capture.startCapturing(copies: 1)
        receive(capture)
        capture.requestJoin(copy: 1)
        #expect(capture.feeds[1].joinedAt == nil, "nothing before the real-time thread picks it up")
        #expect(capture.feeds[1].ring.availableFrames == 0)

        receive(capture)

        #expect(capture.feeds[1].joinedAt == 480)
        #expect(capture.feeds[1].ring.availableFrames == 480)
        #expect(capture.feeds[0].ring.availableFrames == 960)
        #expect(capture.feeds[0].joinedAt == nil, "the other Copy's join frame is left alone")
        #expect(capture.takeFrameCount == 960)
    }

    @Test("A Copy no longer fed gets no more audio; the other goes on")
    func stopFeedingOne() {
        let capture = capture()
        capture.startCapturing(copies: 2)
        receive(capture)
        capture.disable(copy: 0)
        receive(capture)
        #expect(capture.feeds[0].ring.availableFrames == 480)
        #expect(capture.feeds[1].ring.availableFrames == 960)
    }

    @Test("With Pre-roll, both Copies join on the same block, at the Pre-roll's length, and the Pre-roll start is set there")
    func preRollJoinsBothTogether() {
        let capture = capture(preRollSeconds: 1)
        receive(capture)
        receive(capture)                                     // Armed: the Pre-roll holds 960 frames
        capture.startCapturing(copies: 2, preRollFrames: 960)
        #expect(capture.awaitingFirstBlock)
        #expect(capture.feeds.allSatisfy { $0.joinedAt == nil })

        receive(capture)

        #expect(!capture.awaitingFirstBlock)
        #expect(capture.feeds.map(\.joinedAt) == [960, 960])
        #expect(capture.preRollStart.load(ordering: .acquiring) == 960)
        #expect(capture.feeds.map(\.ring.availableFrames) == [480, 480])
        #expect(capture.takeFrameCount == 1_440)
    }

    @Test("A Copy joining on a block that comes after lost input joins before the loss, which goes into it as a drop")
    func joinAcrossInputGap() {
        let capture = capture()
        capture.startCapturing(copies: 1)
        receive(capture, at: 1)
        capture.requestJoin(copy: 1)

        receive(capture, at: 1 + 480 + 4_800)               // 4,800 frames of input lost

        #expect(capture.feeds[1].joinedAt == 480)
        #expect(capture.feeds[1].ring.nextDrop(final: true) == .init(storedFrames: 0, length: 4_800))
        #expect(capture.takeFrameCount == 480 + 4_800 + 480)
    }

    @Test("A Copy whose Pre-roll was no longer there starts with silence up to its join frame, kept as a Gap")
    func lostPreRollHeadIsAGap() throws {
        let ring = SampleRing(channelCount: 1, capacity: 1_000)
        let stem = TakeWriterDropTests.MemoryStem()
        let writer = TakeWriter(feed: CopyFeed(ring: ring, joinedAt: 480), stems: [stem], commitInterval: 48_000, head: { nil })
        TakeWriterDropTests().write(ring, from: 1, count: 100)
        writer.start()
        writer.stop()
        #expect(stem.samples == [Float](repeating: 0, count: 480) + (1...100).map(Float.init))
        #expect(writer.gaps == [0..<480])
    }
}

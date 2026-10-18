import AudioIO
import BroadcastWave
import Foundation
@testable import Recording
import Synchronization
import Testing

/// Stop's wait for the writers (#817) with time and progress under the test's control, so nothing depends on how fast the
/// machine runs: the clock moves only when the test moves it, and it moves only after the writer has done what the test let it.
@Suite("Waiting for the writers")
struct WaitAllTests {
    /// A clock the test moves.
    final class ManualClock: @unchecked Sendable {
        private let lock = NSLock()
        private let base = ContinuousClock.now
        private var offset = Duration.zero
        func advance(_ by: Duration) { lock.withLock { offset += by } }
        var now: ContinuousClock.Instant { lock.withLock { base + offset } }
    }

    /// A Stem whose appends and finalizes each wait for a token from the test (bounded, so a mistake fails and doesn't hang).
    final class TokenStem: StemSink, @unchecked Sendable {
        private let appends = DispatchSemaphore(value: 0)
        private let finalizes = DispatchSemaphore(value: 0)
        let gatesAppends: Bool, gatesFinalize: Bool
        private let lock = NSLock()
        private var count: UInt64 = 0
        init(gatesAppends: Bool = false, gatesFinalize: Bool = false) {
            self.gatesAppends = gatesAppends
            self.gatesFinalize = gatesFinalize
        }
        func allowAppend() { appends.signal() }
        func allowFinalize() { finalizes.signal() }
        var frameCount: UInt64 { lock.withLock { count } }
        func append(_ samples: UnsafeBufferPointer<Float>) throws {
            if gatesAppends { _ = appends.wait(timeout: .now() + 60) }
            lock.withLock { count += UInt64(samples.count) }
        }
        func commitHeader() throws {}
        func finalize() throws { if gatesFinalize { _ = finalizes.wait(timeout: .now() + 60) } }
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { markers.count }
    }

    private func ring(chunks: Int) -> SampleRing {
        let ring = SampleRing(channelCount: 1, capacity: 4_096 * (chunks + 1))
        var samples = [Float](repeating: 0.25, count: 4_096 * chunks)
        samples.withUnsafeMutableBufferPointer { buffer in
            var pointer = UnsafePointer(buffer.baseAddress!)
            withUnsafePointer(to: &pointer) {
                ring.write(AudioBlock(channels: $0, channelCount: 1, frameCount: 4_096 * chunks, hostTime: 0))
            }
        }
        return ring
    }

    /// Gives the writer as long as it needs to finish (bounded, so a mistake fails and doesn't hang); the clock is not moving.
    private func waitUntilFinished(_ writer: TakeWriter) {
        let deadline = ContinuousClock.now + .seconds(60)
        while !writer.isFinished, ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.001) }
    }

    /// Lets the writer do one thing (`release`), and returns once its progress count has moved.
    private func letProgress(_ writer: TakeWriter, _ release: () -> Void) {
        let before = writer.progressCount
        release()
        let deadline = ContinuousClock.now + .seconds(60)
        while writer.progressCount == before, ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.001) }
    }

    @Test("A writer that keeps making progress is waited for, however much fake time passes; each step is under a second")
    func slowButProgressing() {
        let stem = TokenStem(gatesAppends: true)
        let writer = TakeWriter(feed: CopyFeed(ring: ring(chunks: 12), joinedAt: 0), stems: [stem], commitInterval: Int.max / 2)
        writer.start()
        writer.requestStop()
        let clock = ManualClock()
        var released = 0
        TakeWriter.waitAll([writer], noProgressFor: .seconds(5), now: { clock.now }, onPoll: {
            if released < 12 {
                released += 1
                letProgress(writer) { stem.allowAppend() }
            }
            // 0.9 s per step: 12 steps are 10.8 s, more than twice the window, with progress at every look. Once the last is
            // released the clock stops, and the writer is given as long as it needs to finish.
            if released < 12 { clock.advance(.milliseconds(900)) }
            if released == 12 { waitUntilFinished(writer) }
        })
        #expect(!writer.wasAbandoned)
        #expect(writer.isFinished)
        #expect(stem.frameCount == 4_096 * 12)
    }

    @Test("A writer that makes no progress is abandoned once the window has passed")
    func hungIsAbandoned() {
        let stem = TokenStem(gatesAppends: true)
        let writer = TakeWriter(feed: CopyFeed(ring: ring(chunks: 3), joinedAt: 0), stems: [stem], commitInterval: Int.max / 2)
        writer.start()
        writer.requestStop()
        let clock = ManualClock()
        // Let the writer reach its first, held append, so what follows is no progress.
        Thread.sleep(forTimeInterval: 0.2)
        TakeWriter.waitAll([writer], noProgressFor: .seconds(5), now: { clock.now }, onPoll: { clock.advance(.milliseconds(900)) })
        #expect(writer.wasAbandoned)
        for _ in 0..<3 { stem.allowAppend() }  // let the abandoned thread end
    }

    @Test("Finalizing each Stem counts as progress: six Stems finalized a step apart outlast the window")
    func finalizeCountsAsProgress() {
        let stems = (0..<6).map { _ in TokenStem(gatesFinalize: true) }
        let writer = TakeWriter(feed: CopyFeed(ring: SampleRing(channelCount: 6, capacity: 4_096), joinedAt: 0), stems: stems, commitInterval: Int.max / 2)
        writer.start()
        writer.requestStop()
        let clock = ManualClock()
        var released = 0
        TakeWriter.waitAll([writer], noProgressFor: .seconds(5), now: { clock.now }, onPoll: {
            if released < 6 {
                released += 1
                let stem = stems[released - 1]
                letProgress(writer) { stem.allowFinalize() }
            }
            if released < 6 { clock.advance(.milliseconds(900)) } else { waitUntilFinished(writer) }
        })
        #expect(!writer.wasAbandoned)
        #expect(writer.isFinished)
    }
}

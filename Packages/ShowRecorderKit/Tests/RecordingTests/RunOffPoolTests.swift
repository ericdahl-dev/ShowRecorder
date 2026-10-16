import Foundation
@testable import Recording
import Testing

/// `runOffPool` (#681): file work that can block runs on its own thread, so it never holds a cooperative pool thread.
struct RunOffPoolTests {
    @Test("Returns the work's result, from a thread that is not a pool thread")
    func returnsResult() async {
        let onNamedThread = await runOffPool { Thread.current.name == "ShowRecorder off-pool work" }
        #expect(onNamedThread)
        #expect(await runOffPool { 42 } == 42)
    }

    @Test("Runs while pool threads are parked, and its result still comes back", .timeLimit(.minutes(1)))
    func runsWhilePoolIsParked() async throws {
        let poolGate = TestGate()
        let parked = NSLock()
        nonisolated(unsafe) var parkedCount = 0
        let holders = (0..<ProcessInfo.processInfo.activeProcessorCount * 2).map { _ in
            Task.detached {
                parked.withLock { parkedCount += 1 }
                poolGate.wait()
            }
        }
        // At least one pool thread really is parked before the work starts. (Waiting here sleeps this thread: awaiting
        // could not resume once the holders have taken the rest of the pool.)
        try waitUntilBlocking(timeout: .seconds(20)) { parked.withLock { parkedCount } >= 1 }
        let start = ContinuousClock.now
        // The work frees the pool itself: the awaiting test body needs a pool thread to resume on.
        let value = await runOffPool {
            poolGate.open()
            return 7
        }
        #expect(value == 7)
        // Far below `hangGuard`: had the work needed a pool thread it would have waited for the gate's timeout.
        #expect(ContinuousClock.now - start < .seconds(30))
        poolGate.open()
        for holder in holders { await holder.value }
    }
}

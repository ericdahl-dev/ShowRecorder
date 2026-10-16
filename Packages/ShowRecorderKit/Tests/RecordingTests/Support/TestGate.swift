import Foundation

/// A gate a Stem stub waits on, held shut until the test opens it (a Drive pulled mid-write, a dying stick). The wait is
/// bounded (#681): the stubs run on Repair's tasks, so each one parked here holds a cooperative pool thread, and the test
/// body that would open the gate needs one too. With enough of them waiting at once on a small runner none can run, and
/// an unbounded wait never ends. After `timeout` (`hangGuard`) the stub carries on and the test fails or passes slowly
/// instead of wedging the whole run.
final class TestGate: @unchecked Sendable {
    private let lock = NSCondition()
    private var stalled = true

    func wait(timeout: Duration = hangGuard) {
        let deadline = Date(timeIntervalSinceNow: Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18)
        lock.lock()
        while stalled, lock.wait(until: deadline) {}
        lock.unlock()
    }

    func open() {
        lock.lock()
        stalled = false
        lock.broadcast()
        lock.unlock()
    }
}

import Foundation
import Testing

/// The gate the Stem stubs wait on (#681): a stub that blocks a pool thread must give it back after `hangGuard` even if
/// the test that should open the gate can't run (every pool thread waiting on a gate starves the rest of the run).
@Suite("Test gate")
struct TestGateTests {
    @Test("A gate nobody opens stops waiting after its timeout; one that is opened lets the waiter go at once")
    func bounded() {
        let never = TestGate()
        let start = ContinuousClock.now
        never.wait(timeout: .milliseconds(100))
        #expect(ContinuousClock.now - start < .seconds(10), "returned after the timeout instead of waiting for ever")

        let opened = TestGate()
        opened.open()
        let again = ContinuousClock.now
        opened.wait(timeout: .seconds(60))
        #expect(ContinuousClock.now - again < .seconds(10), "an open gate doesn't wait")
    }
}

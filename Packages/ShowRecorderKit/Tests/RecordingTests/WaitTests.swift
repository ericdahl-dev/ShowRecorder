import Foundation
import Testing

/// The tests' wait helper fails the test when its condition never comes true, instead of carrying on (#323).
@Suite("Wait helper")
struct WaitTests {
    @Test("A condition that comes true ends the wait")
    func comesTrue() async throws {
        let start = ContinuousClock.now
        var calls = 0
        try await waitUntil { calls += 1; return calls >= 3 }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test("A condition that never comes true fails the test at the timeout")
    func timesOut() async {
        await withKnownIssue {
            try await waitUntil(timeout: .milliseconds(50)) { false }
        }
    }

    @Test("The blocking form fails the same way")
    func blockingTimesOut() {
        withKnownIssue {
            try waitUntilBlocking(timeout: .milliseconds(50)) { false }
        }
    }
}

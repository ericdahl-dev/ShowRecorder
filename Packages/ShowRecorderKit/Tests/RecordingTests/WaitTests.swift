import Foundation
import Testing

/// The tests' wait helper fails the test when its condition never comes true, instead of carrying on (#323).
@Suite("Wait helper")
struct WaitTests {
    @Test("A condition that comes true ends the wait")
    func comesTrue() async throws {
        var calls = 0
        try await waitUntil { calls += 1; return calls >= 3 }
        // Counted, not timed: a loaded CI runner made a 1-second wall-clock bound flake (1.46 s on #390).
        #expect(calls == 3)
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

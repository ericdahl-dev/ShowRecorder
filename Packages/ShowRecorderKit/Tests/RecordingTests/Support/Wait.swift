import Foundation
import Testing

/// Thrown when a wait runs out, after the failure is recorded, so the test stops there instead of checking a state
/// that never came (#323).
struct WaitTimedOut: Error {}

/// Waits until `condition` holds, checking every 5 ms. If it doesn't by `timeout`, the test fails at the caller's line
/// and this throws. The timeout is generous: under a loaded machine a short one is what made tests flaky.
/// It runs on the caller's actor (`isolation`), so a main-actor test can check main-actor state.
func waitUntil(
    timeout: Duration = .seconds(10), isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out after \(timeout) waiting for a condition", sourceLocation: sourceLocation)
            throw WaitTimedOut()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// The same, for code off the main actor that can't await (it sleeps the thread).
func waitUntilBlocking(
    timeout: Duration = .seconds(10), sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out after \(timeout) waiting for a condition", sourceLocation: sourceLocation)
            throw WaitTimedOut()
        }
        Thread.sleep(forTimeInterval: 0.002)
    }
}

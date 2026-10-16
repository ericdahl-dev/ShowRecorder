import Foundation
import Testing

/// Thrown when a wait runs out, after the failure is recorded, so the test stops there instead of checking a state
/// that never came (#323).
struct WaitTimedOut: Error {}

/// The bound that turns a hang into a failure, not a timing budget: a wait returns as soon as its event comes. Under
/// load the shared main actor can hold an event back for tens of seconds (#646), so the guard sits well above that.
let hangGuard: Duration = .seconds(120)

/// Waits until `condition` holds, checking every 5 ms. If it doesn't by `timeout`, the test fails at the caller's line
/// and this throws. The timeout defaults to `hangGuard`: under a loaded machine a short one is what made tests flaky.
/// It also looks at least once per 5 ms of `timeout`, up to 2,000 looks, before giving up, so a starved Mac, where
/// each look is slow, still gets its looks (#462) without a failing wait holding the build lock for many minutes.
/// It runs on the caller's actor (`isolation`), so a main-actor test can check main-actor state.
func waitUntil(
    timeout: Duration = hangGuard, isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    var looks = 0
    while !condition() {
        looks += 1
        guard ContinuousClock.now < deadline || looks < minimumLooks(timeout) else {
            Issue.record("Timed out after \(timeout) waiting for a condition", sourceLocation: sourceLocation)
            throw WaitTimedOut()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// The same, for a condition that awaits (it asks the Recorder to check its Destinations first).
func waitUntilAsync(
    timeout: Duration = hangGuard, isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation, _ condition: () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    var looks = 0
    while await !condition() {
        looks += 1
        guard ContinuousClock.now < deadline || looks < minimumLooks(timeout) else {
            Issue.record("Timed out after \(timeout) waiting for a condition", sourceLocation: sourceLocation)
            throw WaitTimedOut()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// The same, for code off the main actor that can't await (it sleeps the thread).
func waitUntilBlocking(
    timeout: Duration = hangGuard, sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) throws {
    let deadline = ContinuousClock.now + timeout
    var looks = 0
    while !condition() {
        looks += 1
        guard ContinuousClock.now < deadline || looks < minimumLooks(timeout) else {
            Issue.record("Timed out after \(timeout) waiting for a condition", sourceLocation: sourceLocation)
            throw WaitTimedOut()
        }
        Thread.sleep(forTimeInterval: 0.002)
    }
}

/// One look per 5 ms of `timeout`, the most an unloaded Mac would have made, capped at 2,000.
private func minimumLooks(_ timeout: Duration) -> Int {
    min(Int(timeout / .milliseconds(5)), 2_000)
}

/// Waits until `condition` holds, or gives up after `seconds`. Polls rather than sleeping a fixed time, so a slow
/// machine only makes a test slower, never wrong.
@MainActor
func eventually(_ seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

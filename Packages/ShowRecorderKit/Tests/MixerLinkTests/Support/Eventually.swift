/// Waits until `condition` holds, or gives up after `seconds`. Polls rather than sleeping a fixed time, so a slow
/// machine only makes a test slower, never wrong. It also polls at least as many times as `seconds` allows, so a busy
/// main actor (a loaded CI runner) that runs this loop late can't use up the time before the code under test runs.
@MainActor
func eventually(_ seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
    let interval = Duration.milliseconds(5)
    let polls = Int(seconds * 1000 / 5)
    let deadline = ContinuousClock.now + .seconds(seconds)
    var polled = 0
    while polled < polls || ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: interval)
        polled += 1
    }
    return condition()
}

import Foundation
@testable import Recording
import Testing

/// Stop's "no progress for the window" test (#817), with time given, so a suspended app can be tested (#818).
@Suite("Progress watch")
struct ProgressWatchTests {
    let start = ContinuousClock.now

    @Test("No change for the whole window is a stall; any change starts the window again")
    func stallAndProgress() {
        var watch = ProgressWatch(window: .seconds(5), count: 0, at: start)
        // Looking every 0.5 s: progress at 4 s, so the window runs from 4 s to 9 s.
        var stalledAt: Duration?
        for step in 1...40 where stalledAt == nil {
            let time = Duration.milliseconds(step * 500)
            if watch.isStalled(count: time < .seconds(4) ? 0 : 1, at: start + time) { stalledAt = time }
        }
        #expect(stalledAt == .seconds(9))
    }

    @Test("A long gap between looks means this thread was suspended, so the writer was too: it is not a stall")
    func suspendedAppIsNotAStall() {
        var watch = ProgressWatch(window: .seconds(5), count: 3, at: start)
        let early = watch.isStalled(count: 3, at: start + .milliseconds(20))
        // The app was suspended for 40 s; the first look after it sees nothing new.
        let afterSuspension = watch.isStalled(count: 3, at: start + .seconds(40))
        // The window starts again from there: looks every 0.5 s, stalled 5 s after.
        var stalledAt: Duration?
        for step in 1...40 where stalledAt == nil {
            let time = Duration.seconds(40) + .milliseconds(step * 500)
            if watch.isStalled(count: 3, at: start + time) { stalledAt = time }
        }
        #expect(!early)
        #expect(!afterSuspension)
        #expect(stalledAt == .seconds(45))
    }
}

import Foundation
import Testing

@testable import TakeActivity

/// The Live Activity follows the running Take: it starts with it, shows its Markers, and ends with it (#136).
@Suite("Take activity tracker")
struct TakeActivityTrackerTests {
    static let started = Date(timeIntervalSince1970: 1_000)
    static let take = TakeActivityContent(showName: "2026-10-12 Show", takeTitle: "Take 03", startedAt: started, markerCount: 0)

    @Test("A Take starting starts the activity")
    func starts() {
        var tracker = TakeActivityTracker()
        #expect(tracker.next(Self.take) == .start(Self.take))
    }

    @Test("Nothing new while the Take runs asks for nothing")
    func steady() {
        var tracker = TakeActivityTracker()
        _ = tracker.next(Self.take)
        #expect(tracker.next(Self.take) == .none)
    }

    @Test("A new Marker updates the activity")
    func marker() {
        var tracker = TakeActivityTracker()
        _ = tracker.next(Self.take)
        var marked = Self.take
        marked.markerCount = 1
        #expect(tracker.next(marked) == .update(marked))
        #expect(tracker.next(marked) == .none)
    }

    @Test("The Take stopping, or ending on its own, ends the activity once")
    func ends() {
        var tracker = TakeActivityTracker()
        _ = tracker.next(Self.take)
        #expect(tracker.next(nil) == .end)
        #expect(tracker.next(nil) == .none)
    }

    @Test("No Take and none before asks for nothing")
    func idle() {
        var tracker = TakeActivityTracker()
        #expect(tracker.next(nil) == .none)
    }

    @Test("The next Take, after one ended, starts a new activity")
    func nextTake() {
        var tracker = TakeActivityTracker()
        _ = tracker.next(Self.take)
        _ = tracker.next(nil)
        var next = Self.take
        next.takeTitle = "Take 04"
        #expect(tracker.next(next) == .start(next))
    }

    @Test("A different Take with no stop seen in between replaces the activity")
    func replaced() {
        var tracker = TakeActivityTracker()
        _ = tracker.next(Self.take)
        var next = Self.take
        next.takeTitle = "Take 04"
        next.startedAt = Self.started.addingTimeInterval(600)
        #expect(tracker.next(next) == .replace(next))
    }
}

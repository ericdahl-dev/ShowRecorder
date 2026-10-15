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

@Suite("Take activity Marker button (#684)")
struct TakeActivityMarkerButtonTests {
    static let started = Date(timeIntervalSince1970: 1_000)
    static func content(button: Bool = false, limit: Bool = false) -> TakeActivityContent {
        TakeActivityContent(showName: "Show", takeTitle: "Take 01", startedAt: started, markerCount: 0,
                            showsMarkerButton: button, markerLimitReached: limit)
    }

    @Test("Content from a build before the Marker button reads with the button off and no limit reached")
    func oldPayload() throws {
        let old = #"{"showName":"Show","takeTitle":"Take 01","startedAt":1000,"markerCount":2,"problems":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let content = try decoder.decode(TakeActivityContent.self, from: Data(old.utf8))
        #expect(!content.showsMarkerButton)
        #expect(!content.markerLimitReached)
        #expect(content.markerCount == 2)
    }

    @Test("The Marker button fields survive being encoded and decoded")
    func roundTrip() throws {
        let sent = Self.content(button: true, limit: true)
        let back = try JSONDecoder().decode(TakeActivityContent.self, from: JSONEncoder().encode(sent))
        #expect(back == sent)
    }

    @Test("The button appearing (the environment resolves mid-Take) updates the activity; a new Take with it on replaces")
    func buttonAppearsAndNewTake() {
        var tracker = TakeActivityTracker()
        _ = tracker.next(Self.content(button: false))
        #expect(tracker.next(Self.content(button: true)) == .update(Self.content(button: true)))
        var next = Self.content(button: true)
        next.takeTitle = "Take 02"
        #expect(tracker.next(next) == .replace(next))
    }

    @Test("Reaching the Marker limit updates the same Take's activity; it doesn't replace it")
    func limitUpdates() {
        var tracker = TakeActivityTracker()
        _ = tracker.next(Self.content(button: true))
        #expect(tracker.next(Self.content(button: true, limit: true)) == .update(Self.content(button: true, limit: true)))
    }
}

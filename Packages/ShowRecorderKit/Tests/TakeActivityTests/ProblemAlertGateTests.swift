import Foundation
import TakeActivity
import Testing

/// When a problem during a Take should buzz the wrist and light up the iPhone through the Live Activity (#545):
/// once per new problem, never on an ordinary update, and not again for one that flaps.
@Suite("Problem alert gate")
struct ProblemAlertGateTests {
    static let t0 = Date(timeIntervalSince1970: 10_000)
    static let drive = TakeActivityProblem(id: "driveLowSpace", text: "Drive low on space", symbol: "externaldrive")
    static let copy = TakeActivityProblem(id: "copyStopped", text: "A Copy stopped", symbol: "doc.on.doc")
    static let mixer = TakeActivityProblem(id: "mixerLinkLost", text: "Mixer Link lost", symbol: "slider.horizontal.3")

    @Test("A new problem alerts; the same problem still there doesn't again")
    func newOnce() {
        var gate = ProblemAlertGate()
        #expect(gate.alert(for: [], at: Self.t0) == nil)
        #expect(gate.alert(for: [Self.drive], at: Self.t0)?.title == "Drive low on space")
        #expect(gate.alert(for: [Self.drive], at: Self.t0.addingTimeInterval(1)) == nil)
    }

    @Test("A problem that clears updates quietly; one that comes back within a few minutes doesn't buzz again")
    func flapping() {
        var gate = ProblemAlertGate()
        _ = gate.alert(for: [Self.mixer], at: Self.t0)
        #expect(gate.alert(for: [], at: Self.t0.addingTimeInterval(5)) == nil, "recovery is quiet")
        #expect(gate.alert(for: [Self.mixer], at: Self.t0.addingTimeInterval(20)) == nil, "back within the window")
        _ = gate.alert(for: [], at: Self.t0.addingTimeInterval(30))
        #expect(gate.alert(for: [Self.mixer], at: Self.t0.addingTimeInterval(ProblemAlertGate.repeatAfter + 1)) != nil,
                "back long after: a new event")
    }

    @Test("Problems that appear together are one alert naming them all")
    func together() {
        var gate = ProblemAlertGate()
        let alert = gate.alert(for: [Self.copy, Self.drive], at: Self.t0)
        #expect(alert?.title == "A Copy stopped")
        #expect(alert?.body == "Also: Drive low on space. The Take carries on.")
    }

    @Test("A different new problem alerts even soon after another")
    func anotherProblem() {
        var gate = ProblemAlertGate()
        _ = gate.alert(for: [Self.drive], at: Self.t0)
        #expect(gate.alert(for: [Self.drive, Self.copy], at: Self.t0.addingTimeInterval(10))?.title == "A Copy stopped")
    }

    @Test("A single problem's alert says the Take carries on")
    func body() {
        var gate = ProblemAlertGate()
        #expect(gate.alert(for: [Self.copy], at: Self.t0)?.body == "The Take carries on.")
    }

    @Test("A new Take starts fresh: a problem already told in the last Take alerts again")
    func newTake() {
        var gate = ProblemAlertGate()
        _ = gate.alert(for: [Self.drive], at: Self.t0)
        gate.takeStarted()
        #expect(gate.alert(for: [Self.drive], at: Self.t0.addingTimeInterval(5)) != nil)
    }

    @Test("The Live Activity's content carries the problems, and a change in them is an update")
    func contentCarriesProblems() {
        var tracker = TakeActivityTracker()
        let take = TakeActivityContent(showName: "Show", takeTitle: "Take 01", startedAt: Self.t0, markerCount: 0)
        _ = tracker.next(take)
        var withProblem = take
        withProblem.problems = [Self.drive]
        #expect(tracker.next(withProblem) == .update(withProblem))
    }
}

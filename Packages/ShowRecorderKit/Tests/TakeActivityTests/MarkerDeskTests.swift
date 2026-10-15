import Foundation
import Testing
@testable import TakeActivity

/// The Live Activity's Marker button (#684) reaches the running Take through the desk: one Marker per tap.
@MainActor
@Suite("Marker desk")
struct MarkerDeskTests {
    static let t0 = Date(timeIntervalSince1970: 1_000)

    @Test("A tap places a Marker through the app's own path")
    func tapPlaces() {
        let desk = MarkerDesk()
        var placed = 0
        desk.place = { placed += 1; return true }
        #expect(desk.tap(at: Self.t0))
        #expect(placed == 1)
    }

    @Test("With nothing wired (the app isn't running a Take), a tap places nothing")
    func nothingWired() {
        let desk = MarkerDesk()
        #expect(!desk.tap(at: Self.t0))
    }

    @Test("A second tap inside the window is the same tap: one Marker, not two")
    func onePerTap() {
        let desk = MarkerDesk()
        var placed = 0
        desk.place = { placed += 1; return true }
        #expect(desk.tap(at: Self.t0))
        #expect(!desk.tap(at: Self.t0.addingTimeInterval(MarkerDesk.window / 2)))
        #expect(placed == 1)
        #expect(desk.tap(at: Self.t0.addingTimeInterval(MarkerDesk.window + 0.01)), "the next real tap lands")
        #expect(placed == 2)
    }

    @Test("A clock that steps back after a Marker doesn't swallow taps until it catches up")
    func clockStepsBack() {
        let desk = MarkerDesk()
        desk.place = { true }
        #expect(desk.tap(at: Self.t0))
        #expect(desk.tap(at: Self.t0.addingTimeInterval(-60)))
    }

    @Test("A tap that placed nothing (no Take, past the Free limit) doesn't start the window")
    func refusedTapDoesNotBlock() {
        let desk = MarkerDesk()
        var allow = false
        desk.place = { allow }
        #expect(!desk.tap(at: Self.t0))
        allow = true
        #expect(desk.tap(at: Self.t0.addingTimeInterval(0.01)))
    }
}

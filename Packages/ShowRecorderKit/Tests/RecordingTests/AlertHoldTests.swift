import Foundation
@testable import Recording
import Testing

@Suite("Alert hold")
struct AlertHoldTests {
    let battery = ScreenAlert(id: "battery", priority: .power, tone: .warning, text: "Battery 20%")
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test("An alert shows at once")
    func showsAtOnce() {
        var hold = AlertHold()

        #expect(hold.update(battery, at: start) == battery)
    }

    @Test("Cleared within 2 s, it stays")
    func staysForTwoSeconds() {
        var hold = AlertHold()
        _ = hold.update(battery, at: start)

        #expect(hold.update(nil, at: start + 1.9) == battery)
    }

    @Test("Cleared for 2 s, it goes")
    func goesAfterTwoSeconds() {
        var hold = AlertHold()
        _ = hold.update(battery, at: start)

        #expect(hold.update(nil, at: start + 2) == nil)
    }

    @Test("A swiped alert goes at once")
    func releaseGoesAtOnce() {
        var hold = AlertHold()
        _ = hold.update(battery, at: start)
        hold.release()

        #expect(hold.update(nil, at: start + 0.5) == nil)
    }

    @Test("A different alert takes the banner at once")
    func differentAlertSwapsAtOnce() {
        let hot = ScreenAlert(id: "thermal", priority: .power, tone: .warning, text: "Hot")
        var hold = AlertHold()
        _ = hold.update(battery, at: start)

        #expect(hold.update(hot, at: start + 0.5) == hot)
    }

    @Test("A cleared alert is held only for the time left of its 2 s")
    func remainingTime() {
        var hold = AlertHold()
        _ = hold.update(battery, at: start)
        _ = hold.update(nil, at: start + 0.5)

        #expect(hold.remaining(at: start + 0.5) == 1.5)
        #expect(hold.remaining(at: start + 3) == 0)
    }

    @Test("The same alert with new text doesn't restart the hold")
    func newTextKeepsTheHold() {
        var hold = AlertHold()
        _ = hold.update(battery, at: start)
        let lower = ScreenAlert(id: "battery", priority: .power, tone: .warning, text: "Battery 10%")
        _ = hold.update(lower, at: start + 1.5)

        #expect(hold.update(nil, at: start + 2) == nil)
    }

    @Test("An alert released and raised again shows at once")
    func releasedThenRaisedShows() {
        var hold = AlertHold()
        _ = hold.update(battery, at: start)
        hold.release()

        #expect(hold.update(battery, at: start + 0.5) == battery)
    }
}

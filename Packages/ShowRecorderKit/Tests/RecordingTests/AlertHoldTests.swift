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
}

import Foundation
@testable import Recording
import Testing

@Suite("ScreenAlert queue")
struct AlertQueueTests {
    func alert(_ id: String, _ priority: ScreenAlert.Priority, tone: ScreenAlert.Tone = .warning) -> ScreenAlert {
        ScreenAlert(id: id, priority: priority, tone: tone, text: id)
    }

    @Test("Only the highest-priority alert is shown; the rest are counted")
    func showsHighestPriorityAndCountsTheRest() {
        let queue = AlertQueue([
            alert("copy result", .copyResult, tone: .ok),
            alert("no drive", .destination),
            alert("armed failed", .cannotRecord, tone: .critical),
            alert("shortfall", .input),
        ])

        #expect(queue.top?.id == "armed failed")
        #expect(queue.others.map(\.id) == ["no drive", "shortfall", "copy result"])
        #expect(queue.moreCount == 3)
    }

    @Test("A battery or heat warning ranks below a Take stopped or a Copy lost, and above input notices")
    func powerRanksBetweenDestinationAndInput() {
        let queue = AlertQueue([
            alert("shortfall", .input),
            alert("battery", .power),
            alert("copy lost", .destination),
            alert("cannot record", .cannotRecord, tone: .critical),
        ])
        #expect(queue.ordered.map(\.id) == ["cannot record", "copy lost", "battery", "shortfall"])
    }

    @Test("Alerts of equal priority keep the order they were given")
    func equalPriorityKeepsOrder() {
        let queue = AlertQueue([alert("b", .input), alert("a", .input)])

        #expect(queue.top?.id == "b")
        #expect(queue.others.map(\.id) == ["a"])
    }

    @Test("An alert given twice is shown once")
    func duplicatesAreDropped() {
        let queue = AlertQueue([alert("no drive", .destination), alert("no drive", .destination)])

        #expect(queue.moreCount == 0)
    }

    @Test("With nothing to say there is no alert")
    func emptyQueue() {
        let queue = AlertQueue([])

        #expect(queue.top == nil)
        #expect(queue.moreCount == 0)
    }
}

@Suite("Swiped alerts")
struct SwipedAlertsTests {
    let battery = ScreenAlert(id: "battery", priority: .power, tone: .warning, text: "Battery 20%")

    func alert(_ id: String, _ priority: ScreenAlert.Priority, tone: ScreenAlert.Tone = .warning) -> ScreenAlert {
        ScreenAlert(id: id, priority: priority, tone: tone, text: id)
    }

    @Test("A swiped warning is no longer shown")
    func swipedWarningIsHidden() {
        var swiped = SwipedAlerts()
        swiped.swipe(battery)

        #expect(swiped.showing([battery]).isEmpty)
    }

    @Test("A critical alert can't be swiped away")
    func criticalStays() {
        let stopped = ScreenAlert(id: "drive-stopped", priority: .destination, tone: .critical, text: "The Drive stopped.")
        var swiped = SwipedAlerts()
        swiped.swipe(stopped)

        #expect(swiped.showing([stopped]) == [stopped])
    }

    @Test("A green summary can be swiped away, and shows again when its text changes (#698)")
    func greenSummarySwipes() {
        let summary = ScreenAlert(id: "copies", priority: .copyResult, tone: .ok, text: "Device copy: complete (no Drive)")
        let next = ScreenAlert(id: "copies", priority: .copyResult, tone: .ok, text: "Device copy: complete · Drive copy: complete")
        var swiped = SwipedAlerts()
        swiped.swipe(summary)

        #expect(swiped.showing([summary]).isEmpty)
        #expect(swiped.showing([next]) == [next])
    }

    @Test("A note that isn't a warning or a summary (a hint) isn't swiped")
    func infoStays() {
        let hint = ScreenAlert(id: "hint", priority: .hint, tone: .info, text: "Choose an input to Arm.")
        var swiped = SwipedAlerts()
        swiped.swipe(hint)

        #expect(swiped.showing([hint]) == [hint])
    }

    @Test("A swiped warning shows again when its message changes")
    func newTextShowsAgain() {
        var swiped = SwipedAlerts()
        swiped.swipe(battery)
        let lower = ScreenAlert(id: "battery", priority: .power, tone: .warning, text: "Battery 10%")

        #expect(swiped.showing([lower]) == [lower])
    }

    @Test("A swiped warning shows again when its problem clears and comes back")
    func clearedAndBackShowsAgain() {
        var swiped = SwipedAlerts()
        swiped.swipe(battery)
        swiped.forget(absentFrom: [])

        #expect(swiped.showing([battery]) == [battery])
    }

    @Test("Swiping one warning leaves the other alerts showing")
    func othersUnaffected() {
        let shortfall = ScreenAlert(id: "shortfall", priority: .input, tone: .warning, text: "8 of 18 channels")
        var swiped = SwipedAlerts()
        swiped.swipe(battery)
        swiped.forget(absentFrom: [battery, shortfall])

        #expect(swiped.showing([battery, shortfall]) == [shortfall])
    }

    @Test("A swiped warning that turns critical shows again")
    func turnsCriticalShowsAgain() {
        var swiped = SwipedAlerts()
        swiped.swipe(battery)
        var urgent = battery
        urgent.tone = .critical

        #expect(swiped.showing([urgent]) == [urgent])
    }

    @Test("A swiped battery warning stays hidden as the percent drops within its 10% band")
    func batteryBand() {
        let at20 = PowerStatus(batteryLevel: 0.20, charging: .unplugged, thermal: .nominal).alerts
        let at15 = PowerStatus(batteryLevel: 0.15, charging: .unplugged, thermal: .nominal).alerts
        var swiped = SwipedAlerts()
        swiped.swipe(at20[0])

        #expect(swiped.showing(at15).isEmpty)
    }

    // MARK: - Good news fades (#758)

    @Test("A green good-news banner fades 10 s after it first shows; a blue hint, which is something to do, doesn't (#758)")
    func goodNewsFades() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let copies = alert("copies", .copyResult, tone: .ok), hint = alert("hint", .hint, tone: .info)
        var swiped = SwipedAlerts()
        #expect(swiped.fade([copies, hint], at: start) == start.addingTimeInterval(10))
        #expect(swiped.fade([copies, hint], at: start.addingTimeInterval(9.9)) == start.addingTimeInterval(10))
        #expect(swiped.showing([copies, hint]).map(\.id) == ["copies", "hint"])
        #expect(swiped.fade([copies, hint], at: start.addingTimeInterval(10)) == nil)
        #expect(swiped.showing([copies, hint]).map(\.id) == ["hint"], "the green one faded, as if swiped; the hint stays")
    }

    @Test("A green banner behind a warning isn't on screen, so it doesn't fade: its 10 s start once it's on top (#758)")
    func fadesOnlyOnTop() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let copies = alert("copies", .copyResult, tone: .ok), battery = alert("battery", .power)
        var swiped = SwipedAlerts()
        #expect(swiped.fade([battery, copies], at: start) == nil)
        #expect(swiped.fade([battery, copies], at: start.addingTimeInterval(60)) == nil)
        #expect(swiped.showing([battery, copies]).map(\.id) == ["battery", "copies"], "not faded unseen")
        swiped.swipe(battery)
        #expect(swiped.fade([battery, copies], at: start.addingTimeInterval(61)) == start.addingTimeInterval(71))
        #expect(swiped.fade([battery, copies], at: start.addingTimeInterval(71)) == nil)
        #expect(swiped.showing([battery, copies]).isEmpty)
    }

    @Test("Leaving the screen pauses the fade: back in front, a green banner gets its full 10 s again, not gone at once (#758)")
    func pausedOffScreen() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let copies = alert("copies", .copyResult, tone: .ok)
        var swiped = SwipedAlerts()
        _ = swiped.fade([copies], at: start)
        swiped.pauseFade()
        let back = start.addingTimeInterval(300)
        #expect(swiped.fade([copies], at: back) == back.addingTimeInterval(10))
        #expect(swiped.showing([copies]).count == 1)
    }

    @Test("A clock set back doesn't hold a green banner past its 10 s (#758)")
    func clockSetBack() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let copies = alert("copies", .copyResult, tone: .ok)
        var swiped = SwipedAlerts()
        _ = swiped.fade([copies], at: start)
        #expect(swiped.fade([copies], at: start.addingTimeInterval(-3_600)) == start.addingTimeInterval(-3_590))
    }

    @Test("Problem banners never fade: a warning or critical alert stays until its problem is gone (#758)")
    func problemsDontFade() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let problems = [alert("no drive", .destination), alert("cannot record", .cannotRecord, tone: .critical)]
        var swiped = SwipedAlerts()
        #expect(swiped.fade(problems, at: start) == nil)
        #expect(swiped.fade(problems, at: start.addingTimeInterval(3_600)) == nil)
        #expect(swiped.showing(problems).count == 2)
    }

    @Test("A faded banner stays away for the same event; new text is a new event and shows again, fading 10 s later (#758)")
    func fadedStaysAway() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var swiped = SwipedAlerts()
        let first = ScreenAlert(id: "copies", priority: .copyResult, tone: .ok, text: "Device copy: complete")
        _ = swiped.fade([first], at: start)
        _ = swiped.fade([first], at: start.addingTimeInterval(10))
        #expect(swiped.fade([first], at: start.addingTimeInterval(60)) == nil)
        #expect(swiped.showing([first]).isEmpty)
        let next = ScreenAlert(id: "copies", priority: .copyResult, tone: .ok, text: "Device copy: complete · Drive copy: complete")
        #expect(swiped.showing([next]).count == 1)
        #expect(swiped.fade([next], at: start.addingTimeInterval(70)) == start.addingTimeInterval(80))
    }
}

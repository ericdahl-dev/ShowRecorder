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
}

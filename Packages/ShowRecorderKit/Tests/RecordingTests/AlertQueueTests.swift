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

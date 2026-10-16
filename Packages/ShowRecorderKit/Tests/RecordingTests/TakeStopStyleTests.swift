import Recording
import Testing

@Suite("How a Take is stopped")
struct TakeStopStyleTests {
    @Test("The iPhone and iPad hold to stop where the rule is on")
    func phoneWithRule() {
        #expect(TakeStopStyle.resolve(isIOS: true, holdToStopAvailable: true) == .hold)
    }

    @Test("iOS keeps tap and confirm where the rule is off")
    func phoneWithoutRule() {
        #expect(TakeStopStyle.resolve(isIOS: true, holdToStopAvailable: false) == .confirm)
    }

    @Test("The Mac keeps click and confirm whatever the rule says")
    func mac() {
        #expect(TakeStopStyle.resolve(isIOS: false, holdToStopAvailable: true) == .confirm)
        #expect(TakeStopStyle.resolve(isIOS: false, holdToStopAvailable: false) == .confirm)
    }
}

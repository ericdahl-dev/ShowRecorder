import Recording
import Testing

@Suite("How a Take is stopped")
struct TakeStopStyleTests {
    @Test("The iPhone holds to stop where the rule is on")
    func phoneWithRule() {
        #expect(TakeStopStyle.resolve(isPhone: true, holdToStopAvailable: true) == .hold)
    }

    @Test("The iPhone keeps tap and confirm where the rule is off")
    func phoneWithoutRule() {
        #expect(TakeStopStyle.resolve(isPhone: true, holdToStopAvailable: false) == .confirm)
    }

    @Test("The Mac keeps click and confirm whatever the rule says")
    func mac() {
        #expect(TakeStopStyle.resolve(isPhone: false, holdToStopAvailable: true) == .confirm)
        #expect(TakeStopStyle.resolve(isPhone: false, holdToStopAvailable: false) == .confirm)
    }
}

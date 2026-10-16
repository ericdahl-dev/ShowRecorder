import Foundation
import Recording
import Testing

@Suite("Hold to stop gesture")
struct HoldToStopGestureTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test("A press fills the ring until it ends")
    func ringFills() {
        var gesture = HoldToStopGesture()
        #expect(!gesture.isFilling)
        gesture.pressBegan(at: t0)
        #expect(gesture.isFilling)
        _ = gesture.pressEnded(at: t0.addingTimeInterval(0.2))
        #expect(!gesture.isFilling)
    }

    @Test("A quick tap or an early release shows the hint and does not stop")
    func earlyRelease() {
        var gesture = HoldToStopGesture()
        gesture.pressBegan(at: t0)
        #expect(gesture.pressEnded(at: t0.addingTimeInterval(0.3)) == .showHint)
    }

    @Test("A finished hold stops, and letting go afterward shows no hint")
    func finishedHold() {
        var gesture = HoldToStopGesture()
        gesture.pressBegan(at: t0)
        gesture.holdCompleted()
        #expect(!gesture.isFilling)
        #expect(gesture.pressEnded(at: t0.addingTimeInterval(1.4)) == .nothing)
    }

    @Test("Letting go at the moment the hold ends shows no hint, whichever callback comes first")
    func releaseAtTheMoment() {
        var gesture = HoldToStopGesture()
        gesture.pressBegan(at: t0)
        #expect(gesture.pressEnded(at: t0.addingTimeInterval(HoldToStopGesture.holdSeconds)) == .nothing)
    }

    @Test("A new press forgets the last hold")
    func newPress() {
        var gesture = HoldToStopGesture()
        gesture.pressBegan(at: t0)
        gesture.holdCompleted()
        _ = gesture.pressEnded(at: t0.addingTimeInterval(1.2))
        gesture.pressBegan(at: t0.addingTimeInterval(5))
        #expect(gesture.pressEnded(at: t0.addingTimeInterval(5.2)) == .showHint)
    }
}

@Suite("Stop hint")
struct StopHintTests {
    @Test("It shows after a tap and clears when its time is up")
    func showsAndExpires() {
        var hint = StopHint()
        #expect(!hint.isShown)
        let token = hint.show()
        #expect(hint.isShown)
        hint.expire(token)
        #expect(!hint.isShown)
    }

    @Test("An earlier tap's timer does not clear a newer hint early")
    func overlappingTaps() {
        var hint = StopHint()
        let first = hint.show()
        let second = hint.show()
        hint.expire(first)
        #expect(hint.isShown)
        hint.expire(second)
        #expect(!hint.isShown)
    }

    @Test("A Take ending clears it at once")
    func clears() {
        var hint = StopHint()
        let token = hint.show()
        hint.clear()
        #expect(!hint.isShown)
        hint.expire(token)
        #expect(!hint.isShown)
    }

    @Test("It stays up for two seconds")
    func duration() {
        #expect(StopHint.seconds == 2)
    }
}

@Suite("Stop style in this build")
struct TakeStopStyleCurrentTests {
    @Test("The Mac keeps confirm; iOS holds only where the rule is on")
    func current() {
        #expect(TakeStopStyle.current(isIOS: false) == .confirm)
        let expected: TakeStopStyle = HoldToStopAvailability.isAvailableInThisBuild ? .hold : .confirm
        #expect(TakeStopStyle.current(isIOS: true) == expected)
    }
}

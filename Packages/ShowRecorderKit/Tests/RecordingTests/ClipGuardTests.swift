import Foundation
@testable import Recording
import Testing

/// Clip protection on the record screen (#448): only during a Take (Eric, 2026-10-13), only when switched on.
@MainActor
@Suite("Clip guard")
struct ClipGuardTests {
    let control = FakeGainControl(gainDb: [1: 30], channelOfUSB: [1: 1])

    func makeGuard(on: Bool) -> ClipGuard {
        let control = control
        let clipGuard = ClipGuard()
        clipGuard.isOn = { on }
        clipGuard.makeProtection = { ClipProtection(control: control, sampleRate: 48_000) }
        return clipGuard
    }

    func feedHot(_ clipGuard: ClipGuard) async {
        for window in ClipProtectionTests.hot { await clipGuard.observe([window]) }
    }

    @Test("Only during a Take: between Takes a hot channel is left alone; in a Take it is turned down; after it, left alone")
    func onlyDuringATake() async {
        let clipGuard = makeGuard(on: true)

        await feedHot(clipGuard)
        #expect(control.gainDb[1] == 30, "between Takes")

        clipGuard.handle(.takeStarted(take: 1))
        await feedHot(clipGuard)
        #expect(control.gainDb[1] == 26, "turned down to put the Peak at -6")

        clipGuard.handle(.takeEnded(TakeEnd(take: 1, reason: .stopped)))
        await feedHot(clipGuard)
        await feedHot(clipGuard)
        #expect(control.gainDb[1] == 26, "after the Take")
    }

    @Test("Switched off, a Take's hot channel is left alone")
    func offLeavesAlone() async {
        let clipGuard = makeGuard(on: false)
        clipGuard.handle(.takeStarted(take: 1))
        await feedHot(clipGuard)
        #expect(control.gainDb[1] == 30)
    }

    @Test("Off by default: the setting starts off")
    func offByDefault() {
        let defaults = UserDefaults(suiteName: "ClipGuardTests-\(UUID().uuidString)")!
        #expect(!ClipProtectionSetting.isOn(in: defaults))
    }

    @Test("A Take that ends while a move waits on the Mixer: the move never starts, so nothing moves between Takes")
    func takeEndsDuringAWait() async {
        let clipGuard = makeGuard(on: true)
        clipGuard.handle(.takeStarted(take: 1))
        control.preampAnswer = { await MainActor.run { clipGuard.handle(.takeEnded(TakeEnd(take: 1, reason: .stopped))) } }

        await feedHot(clipGuard)

        #expect(control.gainDb[1] == 30)
    }

    @Test("Windows read after the recorder stopped, before the Take's end arrives, are left alone")
    func ignoresWindowsAfterTheRecorderStopped() async {
        let clipGuard = makeGuard(on: true)
        var recording = true
        clipGuard.isRecording = { recording }
        clipGuard.handle(.takeStarted(take: 1))
        recording = false

        await feedHot(clipGuard)

        #expect(control.gainDb[1] == 30)
    }

    @Test("Switched off during a Take, it stops at once")
    func switchedOffStopsAtOnce() async {
        let clipGuard = makeGuard(on: true)
        clipGuard.handle(.takeStarted(take: 1))

        clipGuard.switchedOff()
        await feedHot(clipGuard)

        #expect(control.gainDb[1] == 30)
        #expect(clipGuard.active == nil)
    }
}

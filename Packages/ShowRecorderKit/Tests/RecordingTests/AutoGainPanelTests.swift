import AutoGain
import MixerLink
@testable import Recording
import Testing

/// Auto-gain's state on the record screen (#155): it outlives the sheet, so Undo is still there when the sheet opens
/// again, and it is locked while a Take runs (no gain moves during a Take).
@MainActor
@Suite("Auto-gain panel")
struct AutoGainPanelTests {
    func makePanel(_ control: FakeGainControl, source: [Int: Double]) -> AutoGainPanel {
        AutoGainPanel(makeSession: { AutoGainSession(control: control, measure: AutoGainSessionTests.meters(control, source: source)) })
    }

    @Test("A run's results and its Undo are kept by the panel, not the sheet")
    func keepsResultsAndUndo() async {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let panel = makePanel(control, source: [1: -40])

        await panel.run([1])

        #expect(panel.results[1] == .set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18))
        #expect(panel.canUndo(1) && panel.canUndoAll)
        await panel.undo(1)
        #expect(control.gainDb[1] == 0)
        #expect(panel.results[1] == nil && !panel.canUndo(1))
    }

    @Test("A Take that starts mid-run stops it at once and locks the panel; no run or Undo until the Take ends")
    func takeStartStopsAndLocks() async {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        var panel: AutoGainPanel!
        var measured = 0
        // The level follows 80% of each move, so USB 1 needs a second move; the Take starts before it.
        panel = AutoGainPanel(makeSession: {
            AutoGainSession(control: control, measure: { usb in
                measured += 1
                if measured == 2 { panel.handle(.takeStarted(take: 1)) }
                return -40 + 0.8 * (control.gainDb[control.channelOfUSB[usb] ?? usb] ?? 0)
            })
        })

        await panel.run([1, 2])

        #expect(panel.results[1] == .haltedForTake(usbChannel: 1, channel: 1))
        #expect(control.gainDb[2] == 0)
        #expect(panel.isLocked)
        let moved = control.gainDb[1]
        await panel.undo(1)
        await panel.run([2])
        #expect(control.gainDb[1] == moved && control.gainDb[2] == 0, "nothing moves during a Take")

        panel.handle(.takeEnded(TakeEnd(take: 1, reason: .stopped)))
        #expect(!panel.isLocked)
        await panel.undo(1)
        #expect(control.gainDb[1] == 0)
    }

    @Test("A Take that starts partway through an Undo stops it before the next step; the rest stays for Undo after the Take")
    func takeStartStopsAnUndo() async {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let panel = AutoGainPanel(makeSession: {
            // 80% follow: two moves to land, so two steps to undo.
            AutoGainSession(control: control, measure: { usb in -40 + 0.8 * (control.gainDb[usb] ?? 0) })
        })
        await panel.run([1])
        let landed = control.gainDb[1]
        // The Take starts while the first undo step is on its way to the Mixer.
        control.undoAnswer = { await MainActor.run { if control.undos == 0 { panel.handle(.takeStarted(take: 1)) } } }

        await panel.undo(1)

        #expect(control.undos == 1, "the step on its way lands; no step after it")
        #expect(control.gainDb[1] != 0 && control.gainDb[1] != landed)
        #expect(panel.canUndo(1))
        #expect(panel.results[1] == .haltedForTake(usbChannel: 1, channel: 1))
    }

    @Test("A second run or Undo asked for while one is under way is refused, so two never move one session at once")
    func oneAtATime() async {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        var panel: AutoGainPanel!
        var asked = false
        panel = AutoGainPanel(makeSession: {
            AutoGainSession(control: control, measure: { usb in
                if !asked { asked = true; await panel.run([2]) }
                return -40 + (control.gainDb[usb] ?? 0)
            })
        })

        await panel.run([1])

        #expect(control.gainDb[2] == 0, "the second run was refused")
        #expect(panel.results[2] == nil)
        #expect(panel.running.isEmpty)
    }

    @Test("While the recorder is recording, nothing runs, even before the Take's event arrives")
    func refusedWhileRecording() async {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let panel = makePanel(control, source: [1: -40])
        panel.isRecording = { true }

        await panel.run([1])

        #expect(control.gainDb[1] == 0)
        #expect(panel.isLocked)
    }
    @Test("Each result can say in plain words what moved to keep the mix, until Undo puts it back (#155, #393)")
    func compensationSummary() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        control.alsoMoves = ReGain.Change(setting: ReGain.Setting(channel: 1, parameter: .mainFader), fromDb: 0, toDb: -22)
        let panel = makePanel(control, source: [1: -40])

        await panel.run([1, 2])

        #expect(panel.compensationSummary(1) == "To keep the mix: fader moved -22.0 dB")
        #expect(panel.compensationSummary(2) == nil)
        await panel.undo(1)
        #expect(panel.compensationSummary(1) == nil)
    }

    typealias Moved = TakeMetadata.GainChange.Compensation

    @Test("Everything moved the same amount, as Re-Gain does, reads as one line: sends and thresholds counted",
          arguments: [
            ([Moved(channel: 1, setting: "fader", fromDb: -5, toDb: -30)], "fader moved -25.0 dB"),
            ([Moved(channel: 1, setting: "fader", fromDb: -5, toDb: -30), Moved(channel: 1, setting: "send 3", fromDb: -10, toDb: -35)],
             "fader and send 3 moved -25.0 dB"),
            ((1...6).map { Moved(channel: 1, setting: "send \($0)", fromDb: 0, toDb: 6) }
                + [Moved(channel: 1, setting: "fader", fromDb: -10, toDb: -4),
                   Moved(channel: 1, setting: "gate threshold", fromDb: -40, toDb: -34),
                   Moved(channel: 1, setting: "compressor threshold", fromDb: -20, toDb: -14)],
             "fader, 6 sends and 2 thresholds moved +6.0 dB"),
            ([Moved(channel: 1, setting: "fader", fromDb: -5, toDb: -11), Moved(channel: 2, setting: "gate threshold", fromDb: -40, toDb: -46)],
             "fader and channel 2's gate threshold moved -6.0 dB"),
          ])
    func sameAmount(moved: [Moved], text: String) {
        #expect(AutoGainPanel.compensationSummary(moved, channel: 1) == "To keep the mix: " + text)
    }

    @Test("When the amounts differ (a setting reached its end), each is listed, signed, from and to")
    func differentAmounts() {
        let moved = [Moved(channel: 1, setting: "fader", fromDb: -80, toDb: -90), Moved(channel: 1, setting: "send 3", fromDb: 5, toDb: -20)]
        #expect(AutoGainPanel.compensationSummary(moved, channel: 1)
                == "To keep the mix: fader -80.0 to -90.0 dB, send 3 +5.0 to -20.0 dB")
    }
}

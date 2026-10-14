import AutoGain
import Foundation
import MixerLink
@testable import Recording
import Testing

/// Auto-gain's state on the record screen (#155): it outlives the sheet, so Undo is still there when the sheet opens
/// again, and it is locked while a Take runs (no gain moves during a Take).
@MainActor
@Suite("Mixer gain: auto-gain")
struct MixerGainAutoGainTests {
    func makeMixerGain(_ control: FakeGainControl, source: [Int: Double]) -> MixerGain {
        MixerGain(makeSession: { _ in AutoGainSession(control: control, measure: AutoGainSessionTests.meters(control, source: source)) })
    }

    @Test("A run's results and its Undo are kept by Mixer gain, not the sheet")
    func keepsResultsAndUndo() async {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let mixerGain = makeMixerGain(control, source: [1: -40])

        await mixerGain.run([1])

        #expect(mixerGain.results[1] == .set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18))
        #expect(mixerGain.canUndo(1) && mixerGain.canUndoAll)
        await mixerGain.undo(1)
        #expect(control.gainDb[1] == 0)
        #expect(mixerGain.results[1] == nil && !mixerGain.canUndo(1))
    }

    @Test("A Take that starts mid-run stops it at once and locks auto-gain; no run or Undo until the Take ends")
    func takeStartStopsAndLocks() async {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        var mixerGain: MixerGain!
        var measured = 0
        // The level follows 80% of each move, so USB 1 needs a second move; the Take starts before it.
        mixerGain = MixerGain(makeSession: { _ in
            AutoGainSession(control: control, measure: { usb in
                measured += 1
                if measured == 2 { mixerGain.handle(.takeStarted(take: 1)) }
                return -40 + 0.8 * (control.gainDb[control.channelOfUSB[usb] ?? usb] ?? 0)
            })
        })

        await mixerGain.run([1, 2])

        #expect(mixerGain.results[1] == .haltedForTake(usbChannel: 1, channel: 1))
        #expect(control.gainDb[2] == 0)
        #expect(mixerGain.isLocked)
        let moved = control.gainDb[1]
        await mixerGain.undo(1)
        await mixerGain.run([2])
        #expect(control.gainDb[1] == moved && control.gainDb[2] == 0, "nothing moves during a Take")

        mixerGain.handle(.takeEnded(TakeEnd(take: 1, reason: .stopped)))
        #expect(!mixerGain.isLocked)
        await mixerGain.undo(1)
        #expect(control.gainDb[1] == 0)
    }

    @Test("A Take that starts partway through an Undo stops it before the next step; the rest stays for Undo after the Take")
    func takeStartStopsAnUndo() async {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let mixerGain = MixerGain(makeSession: { _ in
            // 80% follow: two moves to land, so two steps to undo.
            AutoGainSession(control: control, measure: { usb in -40 + 0.8 * (control.gainDb[usb] ?? 0) })
        })
        await mixerGain.run([1])
        let landed = control.gainDb[1]
        // The Take starts while the first undo step is on its way to the Mixer.
        control.undoAnswer = { await MainActor.run { if control.undos == 0 { mixerGain.handle(.takeStarted(take: 1)) } } }

        await mixerGain.undo(1)

        #expect(control.undos == 1, "the step on its way lands; no step after it")
        #expect(control.gainDb[1] != 0 && control.gainDb[1] != landed)
        #expect(mixerGain.canUndo(1))
        #expect(mixerGain.results[1] == .haltedForTake(usbChannel: 1, channel: 1))
    }

    @Test("A second run or Undo asked for while one is under way is refused, so two never move one session at once")
    func oneAtATime() async {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        var mixerGain: MixerGain!
        var asked = false
        mixerGain = MixerGain(makeSession: { _ in
            AutoGainSession(control: control, measure: { usb in
                if !asked { asked = true; await mixerGain.run([2]) }
                return -40 + (control.gainDb[usb] ?? 0)
            })
        })

        await mixerGain.run([1])

        #expect(control.gainDb[2] == 0, "the second run was refused")
        #expect(mixerGain.results[2] == nil)
        #expect(mixerGain.running.isEmpty)
    }

    @Test("While the recorder is recording, nothing runs, even before the Take's event arrives")
    func refusedWhileRecording() async {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let mixerGain = makeMixerGain(control, source: [1: -40])
        mixerGain.isRecording = { true }

        await mixerGain.run([1])

        #expect(control.gainDb[1] == 0)
        #expect(mixerGain.isLocked)
    }
    @Test("Each result can say in plain words what moved to keep the mix, until Undo puts it back (#155, #393)")
    func compensationSummary() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        control.alsoMoves = MixHold.Change(setting: MixHold.Setting(channel: 1, parameter: .mainFader), fromDb: 0, toDb: -22)
        let mixerGain = makeMixerGain(control, source: [1: -40])

        await mixerGain.run([1, 2])

        #expect(mixerGain.compensationSummary(1) == "To keep the mix: fader moved -22.0 dB")
        #expect(mixerGain.compensationSummary(2) == nil)
        await mixerGain.undo(1)
        #expect(mixerGain.compensationSummary(1) == nil)
    }

    typealias Moved = TakeMetadata.GainChange.Compensation

    @Test("Everything moved the same amount, as Mix Hold does, reads as one line: sends and thresholds counted",
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
        #expect(MixerGain.compensationSummary(moved, channel: 1) == "To keep the mix: " + text)
    }

    @Test("When the amounts differ (a setting reached its end), each is listed, signed, from and to")
    func differentAmounts() {
        let moved = [Moved(channel: 1, setting: "fader", fromDb: -80, toDb: -90), Moved(channel: 1, setting: "send 3", fromDb: 5, toDb: -20)]
        #expect(MixerGain.compensationSummary(moved, channel: 1)
                == "To keep the mix: fader -80.0 to -90.0 dB, send 3 +5.0 to -20.0 dB")
    }

    @Test("While a run goes, Mixer gain counts channels done of the run's total, each row has its phase, and results land as each finishes (#155)")
    func progress() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        let meters = AutoGainSessionTests.meters(control, source: [1: -40])
        var mixerGain: MixerGain!
        var seen: [(progress: MixerGain.Progress?, phase1: AutoGainSession.Phase?, result2: Bool)] = []
        mixerGain = MixerGain(makeSession: { _ in
            AutoGainSession(control: control, measure: { usb in
                if usb == 1 { seen.append((mixerGain.progress, mixerGain.phases[1], mixerGain.results[2] != nil)) }
                return await meters(usb)
            }, settle: { await Task.yield() })
        })

        await mixerGain.run([1, 2])

        #expect(seen.first?.progress == MixerGain.Progress(done: 0, total: 2))
        #expect(seen.first?.phase1 == .measuring)
        #expect(seen.last?.progress == MixerGain.Progress(done: 1, total: 2), "USB 2 had no signal and finished first")
        #expect(seen.last?.result2 == true, "its result showed before the run ended")
        #expect(mixerGain.progress == nil)
        #expect(mixerGain.phases.isEmpty)
        #expect(mixerGain.results.count == 2)
        #expect(mixerGain.finishedRuns == 1, "VoiceOver hears the run finish")
        #expect(mixerGain.lastRunTotal == 2)
    }
    @Test("Progress reads in plain words", arguments: [(0, 16, "0 of 16 channels done"), (7, 16, "7 of 16 channels done"),
                                                      (0, 1, "0 of 1 channel done")])
    func progressText(done: Int, total: Int, text: String) {
        #expect(MixerGain.Progress(done: done, total: total).text == text)
    }

    @Test("A row says where its channel is in plain words; a done one shows its result instead",
          arguments: [(AutoGainSession.Phase.waiting, "Waiting…" as String?), (.measuring, "Listening…"),
                      (.adjusting, "Setting the gain…"),
                      (.done(.skipped(usbChannel: 1, reason: .noSignal)), nil)])
    func phaseLabel(phase: AutoGainSession.Phase, label: String?) {
        #expect(phase.label == label)
    }
    @Test("A Take that starts while a run is still working out its channels leaves no row waiting and moves nothing")
    func stopDuringFirstPass() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        let mixerGain = makeMixerGain(control, source: [1: -40, 2: -40])
        control.preampAnswer = { await MainActor.run { mixerGain.handle(.takeStarted(take: 1)) } }

        await mixerGain.run([1, 2])

        #expect(mixerGain.phases.isEmpty)
        #expect(mixerGain.progress == nil)
        #expect(control.gainDb == [1: 0, 2: 0])
    }

    @Test("Undo belongs to the mixer it was made on: linked to another one, it's dropped with a note and nothing is written (#508)")
    func undoIsForItsOwnMixer() async {
        let foh = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let mon = FakeGainControl(gainDb: [1: 5], channelOfUSB: [1: 1])
        var control = foh, mixer: String? = "XR18-FOH"
        let mixerGain = MixerGain(makeSession: { _ in
            AutoGainSession(currentControl: { control }, measure: { usb in -40 + (control.gainDb[usb] ?? 0) })
        })
        mixerGain.mixerName = { mixer }
        await mixerGain.run([1])
        #expect(mixerGain.canUndo(1))

        // The Mixer Link drops and comes back on the same mixer: Undo still there.
        mixer = nil
        #expect(mixerGain.canUndo(1) && mixerGain.notice == nil)
        mixer = "XR18-FOH"
        #expect(mixerGain.canUndo(1))

        // Linked to another mixer: Undo is gone, the sheet says why, and Undo writes nothing to it.
        control = mon; mixer = "XR18-MON"
        #expect(!mixerGain.canUndo(1) && !mixerGain.canUndoAll)
        #expect(mixerGain.notice == "Undo was for another mixer (XR18-FOH), so it's gone.")
        await mixerGain.undo(1)
        #expect(mon.gainDb[1] == 5)

        // A new run there starts fresh.
        await mixerGain.run([1])
        #expect(mixerGain.notice == nil && mixerGain.canUndo(1))
    }
}

/// Clip protection on the record screen (#448): only during a Take (Eric, 2026-10-13), only when switched on.
@MainActor
@Suite("Mixer gain: clip protection")
struct MixerGainClipProtectionTests {
    let control = FakeGainControl(gainDb: [1: 30], channelOfUSB: [1: 1])

    func makeMixerGain(on: Bool) -> MixerGain {
        let control = control
        let mixerGain = MixerGain()
        mixerGain.isClipProtectionOn = { on }
        mixerGain.isRecording = { true }
        mixerGain.makeProtection = { _ in ClipProtection(control: control, sampleRate: 48_000) }
        return mixerGain
    }

    func feedHot(_ mixerGain: MixerGain) async {
        for window in ClipProtectionTests.hot { await mixerGain.observe([window]) }
    }

    @Test("Only during a Take: between Takes a hot channel is left alone; in a Take it is turned down; after it, left alone")
    func onlyDuringATake() async {
        let mixerGain = makeMixerGain(on: true)

        await feedHot(mixerGain)
        #expect(control.gainDb[1] == 30, "between Takes")

        mixerGain.handle(.takeStarted(take: 1))
        await feedHot(mixerGain)
        #expect(control.gainDb[1] == 26, "turned down to put the Peak at -6")

        mixerGain.handle(.takeEnded(TakeEnd(take: 1, reason: .stopped)))
        await feedHot(mixerGain)
        await feedHot(mixerGain)
        #expect(control.gainDb[1] == 26, "after the Take")
    }

    @Test("Switched off, a Take's hot channel is left alone")
    func offLeavesAlone() async {
        let mixerGain = makeMixerGain(on: false)
        mixerGain.handle(.takeStarted(take: 1))
        await feedHot(mixerGain)
        #expect(control.gainDb[1] == 30)
    }

    @Test("Off by default: the setting starts off")
    func offByDefault() {
        let defaults = UserDefaults(suiteName: "MixerGainTests-\(UUID().uuidString)")!
        #expect(!ClipProtectionSetting.isOn(in: defaults))
    }

    @Test("A Take that ends while a move waits on the Mixer: the move never starts, so nothing moves between Takes")
    func takeEndsDuringAWait() async {
        let mixerGain = makeMixerGain(on: true)
        mixerGain.handle(.takeStarted(take: 1))
        control.preampAnswer = { await MainActor.run { mixerGain.handle(.takeEnded(TakeEnd(take: 1, reason: .stopped))) } }

        await feedHot(mixerGain)

        #expect(control.gainDb[1] == 30)
    }

    @Test("Windows read after the recorder stopped, before the Take's end arrives, are left alone")
    func ignoresWindowsAfterTheRecorderStopped() async {
        let mixerGain = makeMixerGain(on: true)
        var recording = true
        mixerGain.isRecording = { recording }
        mixerGain.handle(.takeStarted(take: 1))
        recording = false

        let started = ClipProtectionTests.hot.compactMap { mixerGain.meters([$0]) }

        #expect(started.isEmpty)

        #expect(control.gainDb[1] == 30)
    }

    @Test("Switched off during a Take, it stops at once")
    func switchedOffStopsAtOnce() async {
        let mixerGain = makeMixerGain(on: true)
        mixerGain.handle(.takeStarted(take: 1))

        mixerGain.switchedOff()
        await feedHot(mixerGain)

        #expect(control.gainDb[1] == 30)
        #expect(mixerGain.protection == nil)
    }

    @Test("An auto-gain Undo step under way when a Take starts finishes on the Mixer before clip protection's first turn-down (#554)")
    func autoGainFirstOnSharedQueue() async throws {
        let control = FakeGainControl(gainDb: [1: 30, 2: 30], channelOfUSB: [1: 1, 2: 2])
        let mixerGain = MixerGain(makeSession: { queue in
            AutoGainSession(control: control, measure: AutoGainSessionTests.meters(control, source: [2: -40]), queue: queue)
        })
        mixerGain.makeProtection = { queue in ClipProtection(control: control, sampleRate: 48_000, queue: queue) }
        mixerGain.isClipProtectionOn = { true }
        var recording = false
        mixerGain.isRecording = { recording }
        await mixerGain.run([2])
        // The Undo steps written when each turn-down reached the Mixer.
        let (turnDowns, turnDown) = AsyncStream<Int>.makeStream()
        let (probed, probe) = AsyncStream<Void>.makeStream()
        control.answer = { [control] in
            turnDown.yield(await control.undos)
            probe.yield()
        }
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        control.undoAnswer = {
            enter.yield()
            for await _ in released { return }
        }
        let undoing = Task { await mixerGain.undo(2) }
        #expect(await ClipProtectionTests.next(entered), "the Undo step is on the Mixer")
        recording = true
        mixerGain.handle(.takeStarted(take: 1))

        // The preamp read is the turn-down's last call before the queue.
        let (reached, reach) = AsyncStream<Void>.makeStream()
        control.preampAnswer = { reach.yield() }

        let moving = Task { for window in ClipProtectionTests.hot { await mixerGain.observe([window]) } }
        #expect(await ClipProtectionTests.next(reached), "the turn-down reaches the queue")
        // Without a shared queue the turn-down reaches the Mixer in milliseconds.
        #expect(await ClipProtectionTests.next(probed, within: .seconds(1)) == false, "the turn-down waits for the Undo step")
        release.yield()
        release.finish()                                    // a looping Undo can't hang on a second step
        await undoing.value
        await moving.value
        turnDown.finish()
        var written: [Int] = []
        for await undos in turnDowns { written.append(undos) }
        #expect(written == [1], "the Undo step was written before the turn-down")
        #expect(control.gainDb[1] == 26)
    }
}

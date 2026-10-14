import AutoGain
import MixerLink
import TakeFile
@testable import Recording
import Testing

/// A mixer in memory: each mixer channel's preamp gain, and what each USB Channel carries. A USB Channel's level is
/// its source's level plus its channel's gain, as a preamp moves it dB for dB.
@MainActor
final class FakeGainControl: GainControl {
    var gainDb: [Int: Double]
    var channelOfUSB: [Int: Int]
    /// Where the gain really goes, when the mapping is wrong: USB Channel's channel -> the channel actually moved.
    var movesInstead: [Int: Int] = [:]
    /// When set, every gain move fails with it (the Mixer stopped answering).
    var problem: MixerLinkProblem?
    /// When set, undo fails with it from this many undos on (0: the first fails), as a Mixer that stops answering.
    var undoFailsAfter: Int?
    private(set) var undos = 0
    /// Gain moves started on the Mixer.
    private(set) var moveStarts = 0
    /// When set, each gain move waits on it first, as a slow Mixer does.
    var answer: (@Sendable () async -> Void)?
    /// When set, each gain move waits on it with the Mixer channel moving, so a test can hold one channel's move.
    var channelAnswer: (@Sendable (Int) async -> Void)?
    let gainRange: ClosedRange<Double> = -12...60
    /// When set, every gain move stops halfway: the mixer has the half it was sent, and the move throws
    /// `.gainMoveInterrupted` with that half (#450).
    var interruptsHalfway = false
    /// The preamp each Mixer channel's move lands on, when it isn't its own (a shared headamp, a stereo link).
    var preampOf: [Int: Int] = [:]
    /// The lane each Mixer channel is moved in, when it shares one (a strip-linked pair).
    var laneOf: [Int: Int] = [:]
    /// When set, every gain move also moves this compensated setting, even when the gain snaps back to where it was.
    var alsoMoves: MixHold.Change?
    /// When set, each undo waits on it first, as a slow Mixer does.
    var undoAnswer: (@Sendable () async -> Void)?
    /// When set, each preamp read waits on it first, as a slow Mixer does.
    var preampAnswer: (@Sendable () async -> Void)?
    /// When set, Mix Hold can't raise a gain past this, as when a threshold reaches its top: it stops there and says so.
    var mixHoldCeilingDb: Double?
    /// When set, a threshold every move compensates (one keyed from all the channels, say): a move reads it, ramps,
    /// then writes what it read less the gain change, as a Mix Hold plan does. Moves that overlap lose each other's.
    var sharedThresholdDb: Double?
    static let gateAtTop = MixHold.Limit(setting: MixHold.Setting(channel: 1, parameter: .gateThreshold), endDb: 0)

    init(gainDb: [Int: Double], channelOfUSB: [Int: Int]) {
        self.gainDb = gainDb
        self.channelOfUSB = channelOfUSB
    }

    nonisolated func channel(forUSBChannel usbChannel: Int) -> Int? {
        MainActor.assumeIsolated { channelOfUSB[usbChannel] }
    }

    nonisolated func preamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? {
        if let answer = await MainActor.run(body: { preampAnswer }) { await answer() }
        return await MainActor.run { preampOf[channel] ?? channel }
    }

    nonisolated func lane(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? {
        await MainActor.run { laneOf[channel] }
    }

    nonisolated func applyMixHold(channel: Int, gainChangeDb: Double, scopes: MixHold.Scopes) async throws(MixerLinkProblem) -> GainStep {
        await MainActor.run { moveStarts += 1 }
        if let problem = await MainActor.run(body: { problem }) { throw problem }
        if let answer = await MainActor.run(body: { answer }) { await answer() }
        if let channelAnswer = await MainActor.run(body: { channelAnswer }) { await channelAnswer(channel) }
        if let read = await MainActor.run(body: { sharedThresholdDb }) {
            for _ in 0..<5 { await Task.yield() }   // the ramp
            await MainActor.run { sharedThresholdDb = read - gainChangeDb }
        }
        let result: Result<GainStep, MixerLinkProblem> = await MainActor.run {
            let target = movesInstead[channel] ?? channel
            let from = gainDb[target] ?? 0
            var to = min(gainRange.upperBound, max(gainRange.lowerBound, from + gainChangeDb))
            var limit: MixHold.Limit?
            if let ceiling = mixHoldCeilingDb, to > max(from, ceiling) {
                to = max(from, ceiling)
                limit = Self.gateAtTop
            }
            if interruptsHalfway {
                let half = from + (to - from) / 2
                gainDb[target] = half
                let step = GainStep(channel: channel, headamp: target, fromGainDb: from, toGainDb: half, held: [:], limitedBy: nil,
                                    restore: ["gain/\(target)": Float(from)])
                return .failure(.gainMoveInterrupted(step))
            }
            gainDb[target] = to
            let changes = alsoMoves.map { [$0] } ?? []
            let held = Dictionary(changes.map { ($0.setting, $0.toDb) }, uniquingKeysWith: { _, last in last })
            return .success(GainStep(channel: channel, headamp: target, fromGainDb: from, toGainDb: to, changes: changes, held: held,
                                     limitedBy: limit, restore: ["gain/\(target)": Float(from)]))
        }
        return try result.get()
    }

    nonisolated func undo(_ step: GainStep) async throws(MixerLinkProblem) {
        if let answer = await MainActor.run(body: { undoAnswer }) { await answer() }
        let fails = await MainActor.run { () -> Bool in
            if let after = undoFailsAfter, undos >= after { return true }
            undos += 1
            gainDb[step.headamp] = step.fromGainDb
            return false
        }
        if fails { throw .noReply(host: "fake") }
    }
}

@MainActor
@Suite("Auto-gain session")
struct AutoGainSessionTests {
    /// Source levels at 0 dB gain, by USB Channel.
    static func meters(_ control: FakeGainControl, source: [Int: Double]) -> (Int) async -> Double {
        { usb in
            guard let level = source[usb] else { return -120 }
            let channel = control.channelOfUSB[usb] ?? usb
            return level + (control.gainDb[channel] ?? 0)
        }
    }

    @Test("Audio that stops after a gain step (disarmed) ends the channel as no signal: no undo, the step kept for Undo (#554)")
    func audioStopped() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        var measured = 0
        let session = AutoGainSession(control: control, measure: { usb in
            measured += 1
            return measured == 1 ? -40 + (control.gainDb[usb] ?? 0) : nil
        })

        let results = await session.run(usbChannels: [1])

        #expect(results == [.skipped(usbChannel: 1, reason: .noSignal)])
        #expect(control.undos == 0)
        #expect(control.gainDb[1] != 0)
        #expect(session.steps[1]?.count == 1)
    }

    @Test("One channel at -40 dBFS is brought to -18 with its preamp")
    func oneChannel() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        let results = await session.run(usbChannels: [1])

        #expect(results == [.set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18)])
        #expect(control.gainDb[1] == 22)
    }

    @Test("Stopped mid-run (a Take started): no new gain move after it, every channel still moving says so and keeps its moves for Undo")
    func stopMidRun() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        var session: AutoGainSession!
        var measuredUSB1 = 0
        var movesAtStop = 0
        // The level follows 80% of each move, so each channel needs a second move to land; the Take starts before it.
        session = AutoGainSession(control: control, measure: { usb in
            if usb == 1 {
                measuredUSB1 += 1
                if measuredUSB1 == 2 {
                    session.stop()
                    movesAtStop = control.moveStarts
                }
            }
            return -40 + 0.8 * (control.gainDb[control.channelOfUSB[usb] ?? usb] ?? 0)
        }, settle: { await Task.yield() })

        let results = await session.run(usbChannels: [1, 2])

        #expect(results == [.haltedForTake(usbChannel: 1, channel: 1), .haltedForTake(usbChannel: 2, channel: 2)])
        // The Mixer takes one move at a time, so at most the one already on its way when the Take started lands.
        #expect(control.moveStarts <= movesAtStop + 1, "no new gain move after the stop")
        #expect(control.gainDb[1] != 0)
        #expect(session.steps[1]?.isEmpty == false, "kept for Undo")
        try await session.undoAll()
        #expect(control.gainDb == [1: 0, 2: 0])
    }

    @Test("Stopped before any channel moves, nothing moves and no channel is run")
    func stopBeforeMoves() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        var session: AutoGainSession!
        session = AutoGainSession(control: control, measure: { _ in
            session.stop()
            return -40
        })

        let results = await session.run(usbChannels: [1, 2])

        #expect(results == [.haltedForTake(usbChannel: 1, channel: 1), .haltedForTake(usbChannel: 2, channel: 2)])
        #expect(control.gainDb == [1: 0, 2: 0])
    }

    @Test("After the Mixer Link reconnects (a new driver), runs and Undo go through the new one, not the first (#508)")
    func followsTheCurrentControl() async throws {
        let first = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        var current = first
        let session = AutoGainSession(currentControl: { current }, measure: { usb in -40 + (current.gainDb[usb] ?? 0) })
        _ = await session.run(usbChannels: [1])
        #expect(first.gainDb[1] == 22)

        // The Mixer Link reconnects: a new driver on the same Mixer, which holds what the first one wrote.
        let reconnected = FakeGainControl(gainDb: first.gainDb, channelOfUSB: first.channelOfUSB)
        current = reconnected
        _ = await session.run(usbChannels: [2])
        #expect(reconnected.gainDb[2] == 22)
        #expect(first.gainDb[2] == 0, "the old driver isn't used")

        try await session.undo(usbChannel: 1)
        #expect(reconnected.gainDb[1] == 0, "Undo after the reconnect goes through the new driver")
    }

    @Test("An Undo under way when the Mixer Link reconnects to another Mixer stops: nothing of the first Mixer's is written to it (#508)")
    func undoUnderWayNeverWritesToAnotherMixer() async throws {
        let foh = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let mon = FakeGainControl(gainDb: [1: 5], channelOfUSB: [1: 1])
        var current = foh, mixer: String? = "FOH · XR18"
        // The level follows 80% of each move, so two steps to undo.
        // After the first step is undone (it's logged), the Link comes back on another Mixer.
        let session = AutoGainSession(currentControl: { current }, mixer: { mixer }, measure: { usb in -40 + 0.8 * (current.gainDb[usb] ?? 0) },
                                      log: { change in if change.reason == .undo { current = mon; mixer = "MON · XR18" } })
        _ = await session.run(usbChannels: [1])
        #expect(session.steps[1]?.count == 2)

        await #expect(throws: MixerLinkProblem.self) { try await session.undo(usbChannel: 1) }

        #expect(mon.gainDb[1] == 5, "nothing written to the other Mixer")
        #expect(session.steps[1]?.count == 1, "the step left stays, for the first Mixer")
    }

    @Test("An Undo with no gain control (Link down, or the Armed input isn't the linked Mixer) says so honestly (#589)")
    func undoWithNoGainControlSaysWhy() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        var current: FakeGainControl? = control
        let session = AutoGainSession(currentControl: { current }, mixer: { "FOH · XR18" },
                                      measure: { usb in -40 + (control.gainDb[usb] ?? 0) })
        _ = await session.run(usbChannels: [1])
        current = nil

        await #expect(throws: MixerLinkProblem.other(
            "The Mixer Link isn't connected to the Armed input's Mixer, so nothing was written.")) {
            try await session.undo(usbChannel: 1)
        }
    }

    @Test("All channels: silent ones, ones with no Mixer channel, and a second USB Channel on a channel already moved are skipped")
    func skips() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0, 3: 0], channelOfUSB: [1: 1, 2: 2, 3: 3, 4: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40, 4: -40]))

        let results = await session.run(usbChannels: [1, 2, 4, 5])

        #expect(results == [
            .set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18),
            .skipped(usbChannel: 2, reason: .noSignal),
            .skipped(usbChannel: 4, reason: .sameChannel(asUSBChannel: 1)),
            .skipped(usbChannel: 5, reason: .noChannel),
        ])
        #expect(control.gainDb == [1: 22, 2: 0, 3: 0])
    }

    @Test("If the level doesn't follow the gain (the wrong preamp moved), it stops and puts that gain back")
    func levelDidNotFollow() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1])
        control.movesInstead = [1: 2]          // the mapping is wrong: channel 2's preamp moves instead
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        let results = await session.run(usbChannels: [1])

        #expect(results == [.stopped(usbChannel: 1, channel: 1)])
        #expect(control.gainDb == [1: 0, 2: 0], "the wrong preamp is put back")
        #expect(session.steps[1] == nil || session.steps[1] == [], "nothing left to undo")
    }

    @Test("A channel the rule can't bring to target says why, and keeps its gain for Undo")
    func ruleFailure() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: 10]))   // far too hot

        let results = await session.run(usbChannels: [1])

        guard case .failed(usbChannel: 1, channel: 1, failure: let failure, _)? = results.first else {
            Issue.record("expected a failure, got \(results)"); return
        }
        #expect([.rangeReached(levelDbfs: -2), .stillClipping(levelDbfs: -2)].contains(failure), "the preamp is at its -12 dB end")
        #expect(control.gainDb[1] == -12)
        #expect(session.steps[1]?.isEmpty == false)
    }

    @Test("A Mixer that stops answering is reported for that channel, not skipped quietly")
    func mixerError() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        control.problem = .noReply(host: "10.0.0.20")
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        #expect(await session.run(usbChannels: [1]) == [.error(usbChannel: 1, channel: 1, problem: .noReply(host: "10.0.0.20"))])
    }

    @Test("Undo puts one channel's gain back, or every channel's")
    func undo() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 5], channelOfUSB: [1: 1, 2: 2])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40, 2: -30]))
        _ = await session.run(usbChannels: [1, 2])
        #expect(control.gainDb == [1: 22, 2: 12])

        try await session.undo(usbChannel: 2)
        #expect(control.gainDb == [1: 22, 2: 5])

        try await session.undoAll()
        #expect(control.gainDb == [1: 0, 2: 5])
        #expect(session.steps.values.allSatisfy { $0.isEmpty })
    }

    @Test("Every gain step and every Undo is logged, with what Mix Hold moved (#450)")
    func logsGainChanges() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        var logged: [TakeMetadata.GainChange] = []
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]), log: { logged.append($0) })

        _ = await session.run(usbChannels: [1])
        try await session.undo(usbChannel: 1)

        #expect(logged.map(\.reason) == [.autoGain, .undo])
        #expect(logged.map(\.fromGainDb) == [0, 22])
        #expect(logged.map(\.toGainDb) == [22, 0])
        #expect(logged.allSatisfy { $0.usbChannel == 1 && $0.channel == 1 && $0.headamp == 1 })
    }

    @Test("A safety stop's Undo is logged too")
    func logsSafetyUndo() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1])
        control.movesInstead = [1: 2]
        var logged: [TakeMetadata.GainChange] = []
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]), log: { logged.append($0) })

        _ = await session.run(usbChannels: [1])

        #expect(logged.map(\.reason) == [.autoGain, .undo])
    }

    @Test("Running a USB Channel again keeps the earlier run's moves for Undo, so Undo puts the gain back where it started")
    func undoAfterRerun() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        control.mixHoldCeilingDb = 10
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        _ = await session.run(usbChannels: [1])
        _ = await session.run(usbChannels: [1])
        #expect(control.gainDb[1] == 10)
        try await session.undo(usbChannel: 1)

        #expect(control.gainDb[1] == 0)
    }

    @Test("When Mix Hold can't go further, the result says which setting stopped it, not that the preamp ran out")
    func limitNamed() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        control.mixHoldCeilingDb = 10
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        let results = await session.run(usbChannels: [1])

        #expect(results == [.failed(usbChannel: 1, channel: 1, failure: .rangeReached(levelDbfs: -30), limitedBy: FakeGainControl.gateAtTop)])
    }

    @Test("A Mix Hold limit reads as the setting that stopped it and its end stop",
          arguments: [(MixHold.Limit(setting: .init(channel: 1, parameter: .gateThreshold), endDb: 0),
                       "Channel 1's gate threshold is at its end stop (0 dB)"),
                      (MixHold.Limit(setting: .init(channel: 3, parameter: .mainFader), endDb: -90),
                       "Channel 3's fader is at its end stop (-90 dB)"),
                      (MixHold.Limit(setting: .init(channel: 2, parameter: .send(4)), endDb: 10),
                       "Channel 2's send 4 is at its end stop (+10 dB)")])
    func limitText(limit: MixHold.Limit, text: String) {
        #expect(limit.explanation == text)
    }

    @Test("An Undo the Mixer stops answering halfway keeps the steps it didn't undo, and a second Undo finishes the job")
    func undoFailsHalfway() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))
        control.mixHoldCeilingDb = 10
        _ = await session.run(usbChannels: [1])          // 0 -> 10
        control.mixHoldCeilingDb = 20
        _ = await session.run(usbChannels: [1])          // 10 -> 20
        control.undoFailsAfter = 1

        await #expect(throws: MixerLinkProblem.self) { try await session.undo(usbChannel: 1) }
        #expect(control.gainDb[1] == 10)
        #expect(session.steps[1]?.count == 1)
        control.undoFailsAfter = nil
        try await session.undo(usbChannel: 1)

        #expect(control.gainDb[1] == 0)
        #expect(session.steps[1]?.isEmpty ?? true)
    }

    @Test("When the level doesn't follow and putting the gain back fails, the move stays for Undo and the result says why")
    func stoppedUndoFails() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1])
        control.movesInstead = [1: 2]   // the gain lands on another channel, so USB 1's level doesn't follow
        control.undoFailsAfter = 0
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        let results = await session.run(usbChannels: [1])

        // Not "stopped", which says the gain was put back: it wasn't, so the Mixer's problem is the result.
        #expect(results == [.error(usbChannel: 1, channel: 1, problem: .noReply(host: "fake"))])
        #expect(session.steps[1]?.count == 1)
        control.undoFailsAfter = nil
        try await session.undo(usbChannel: 1)
        #expect(control.gainDb[2] == 0)
    }

    @Test("Undo tapped twice while the first is still waiting on the Mixer undoes each step once")
    func overlappingUndos() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))
        control.mixHoldCeilingDb = 10
        _ = await session.run(usbChannels: [1])          // 0 -> 10
        control.mixHoldCeilingDb = 20
        _ = await session.run(usbChannels: [1])          // 10 -> 20
        control.undoAnswer = { try? await Task.sleep(for: .milliseconds(20)) }

        async let first: Void = try session.undo(usbChannel: 1)
        async let second: Void = try session.undo(usbChannel: 1)
        _ = try await (first, second)

        #expect(control.gainDb[1] == 0)
        #expect(control.undos == 2)
    }

    @Test("A step whose gain snapped back but which still moved a setting is kept for Undo and logged")
    func settingMovedWithoutGain() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        control.mixHoldCeilingDb = 0   // the gain can't go up at all
        let fader = MixHold.Setting(channel: 1, parameter: .mainFader)
        control.alsoMoves = MixHold.Change(setting: fader, fromDb: 9.8, toDb: 10)
        var logged: [TakeMetadata.GainChange] = []
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]), log: { logged.append($0) })

        _ = await session.run(usbChannels: [1])

        #expect(session.steps[1]?.count == 1)
        #expect(logged.count == 1)
    }

    @Test("Two Mixer channels on one preamp (a shared X32 headamp, a stereo link) move it once; the other is skipped (#458)")
    func samePreamp() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        control.preampOf = [2: 1]
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40, 2: -40]))

        let results = await session.run(usbChannels: [1, 2])

        #expect(results == [
            .set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18),
            .skipped(usbChannel: 2, reason: .samePreamp(asUSBChannel: 1)),
        ])
    }

    @Test("A gain move the mixer stops answering partway is logged with what was written and kept for Undo (#450)")
    func interruptedMoveLoggedAndUndone() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        control.interruptsHalfway = true
        var logged: [TakeMetadata.GainChange] = []
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]), log: { logged.append($0) })

        let results = await session.run(usbChannels: [1])

        guard case .error(usbChannel: 1, channel: 1, problem: .gainMoveInterrupted)? = results.first else {
            Issue.record("expected the interrupted move as the result, got \(results)")
            return
        }
        #expect(logged.map(\.toGainDb) == [11])
        #expect(session.steps[1]?.count == 1)
        control.interruptsHalfway = false
        try await session.undo(usbChannel: 1)
        #expect(control.gainDb[1] == 0)
    }

    @Test("All channels are measured and stepped together, each on its own USB Channel, not one after another (#155)")
    func inParallel() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        let meters = Self.meters(control, source: [1: -40, 2: -30])
        var measured: [Int] = []
        let session = AutoGainSession(control: control, measure: { usb in
            measured.append(usb)
            return await meters(usb)
        }, settle: { await Task.yield() })

        let results = await session.run(usbChannels: [1, 2])

        #expect(results == [
            .set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18),
            .set(usbChannel: 2, channel: 2, fromGainDb: 0, toGainDb: 12, levelDbfs: -18),
        ])
        // USB Channel 2 is measured before USB Channel 1 is done.
        let firstOf2 = try #require(measured.firstIndex(of: 2))
        let lastOf1 = try #require(measured.lastIndex(of: 1))
        #expect(firstOf2 < lastOf1, "measured in order \(measured)")
    }
    @Test("Run together, a channel whose level doesn't follow is stopped and put back; the others still reach target (#155)")
    func oneStopsOthersFinish() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0, 3: 0], channelOfUSB: [1: 1, 2: 2])
        control.movesInstead = [2: 3]   // USB Channel 2's move lands on channel 3
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40, 2: -40]),
                                      settle: { await Task.yield() })

        let results = await session.run(usbChannels: [1, 2])

        #expect(results == [
            .set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18),
            .stopped(usbChannel: 2, channel: 2),
        ])
        #expect(control.gainDb == [1: 22, 2: 0, 3: 0])
    }
    @Test("Run together, one channel's move on the Mixer finishes before the next starts, so a setting both compensate keeps both (#155)")
    func movesOneAtATime() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        control.sharedThresholdDb = 0
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40, 2: -30]),
                                      settle: { await Task.yield() })

        _ = await session.run(usbChannels: [1, 2])

        #expect(control.gainDb == [1: 22, 2: 12])
        #expect(control.sharedThresholdDb == -34)
    }
    @Test("An Undo waiting for its turn on the Mixer when a Take starts doesn't move anything (#155)")
    func undoWaitingWhenStopped() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40, 2: -40]))
        _ = await session.run(usbChannels: [1, 2])
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        control.undoAnswer = {
            enter.yield()
            for await _ in released { return }
        }

        let first = Task { try await session.undo(usbChannel: 1) }
        try #require(await ClipProtectionTests.next(entered), "the first Undo is on the Mixer")
        let second = Task { try await session.undo(usbChannel: 2) }   // waits for the Mixer
        await Task.yield()
        session.stop()
        release.yield()
        release.finish()
        try await first.value
        try await second.value

        #expect(control.gainDb[2] == 22, "USB 2's Undo never reached the Mixer")
    }

    @Test("The result can say what Mix Hold compensated on each USB Channel, until Undo puts it back (#155, #393)")
    func compensated() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        control.alsoMoves = MixHold.Change(setting: MixHold.Setting(channel: 1, parameter: .mainFader), fromDb: 0, toDb: -22)
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        _ = await session.run(usbChannels: [1, 2])

        #expect(session.compensated(usbChannel: 1) == [.init(channel: 1, setting: "fader", fromDb: 0, toDb: -22)])
        #expect(session.compensated(usbChannel: 2).isEmpty)   // no signal, nothing moved
        try await session.undo(usbChannel: 1)
        #expect(session.compensated(usbChannel: 1).isEmpty)
    }

    @Test("Each channel says where it is as it goes: waiting, measuring, adjusting, then done with its result (#155)")
    func phases() async throws {
        let control = FakeGainControl(gainDb: [1: 0, 2: 0], channelOfUSB: [1: 1, 2: 2])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))
        var seen: [Int: [AutoGainSession.Phase]] = [:]
        session.onPhase = { usb, phase in seen[usb, default: []].append(phase) }

        _ = await session.run(usbChannels: [1, 2, 3])

        #expect(seen[1] == [.waiting, .measuring, .adjusting, .measuring,
                            .done(.set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18))])
        #expect(seen[2] == [.waiting, .measuring, .done(.skipped(usbChannel: 2, reason: .noSignal))])
        #expect(seen[3] == [.done(.skipped(usbChannel: 3, reason: .noChannel))])
    }
    @Test("A channel already at the target is left alone and says so, rather than giving no result (#155)")
    func alreadyOnTarget() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -18]))

        let results = await session.run(usbChannels: [1])

        #expect(results == [.skipped(usbChannel: 1, reason: .alreadyOnTarget(levelDbfs: -18))])
        #expect(session.steps[1, default: []].isEmpty, "nothing to undo")
    }
}

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
    /// When set, each gain move waits on it first, as a slow Mixer does.
    var answer: (@Sendable () async -> Void)?
    let gainRange: ClosedRange<Double> = -12...60
    /// The preamp each Mixer channel's move lands on, when it isn't its own (a shared headamp, a stereo link).
    var preampOf: [Int: Int] = [:]
    /// When set, every gain move also moves this compensated setting, even when the gain snaps back to where it was.
    var alsoMoves: ReGain.Change?
    /// When set, each undo waits on it first, as a slow Mixer does.
    var undoAnswer: (@Sendable () async -> Void)?
    /// When set, Re-Gain can't raise a gain past this, as when a threshold reaches its top: it stops there and says so.
    var reGainCeilingDb: Double?
    static let gateAtTop = ReGain.Limit(setting: ReGain.Setting(channel: 1, parameter: .gateThreshold), endDb: 0)

    init(gainDb: [Int: Double], channelOfUSB: [Int: Int]) {
        self.gainDb = gainDb
        self.channelOfUSB = channelOfUSB
    }

    nonisolated func channel(forUSBChannel usbChannel: Int) -> Int? {
        MainActor.assumeIsolated { channelOfUSB[usbChannel] }
    }

    nonisolated func preamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? {
        await MainActor.run { preampOf[channel] ?? channel }
    }

    nonisolated func applyReGain(channel: Int, gainChangeDb: Double, scopes: ReGain.Scopes) async throws(MixerLinkProblem) -> GainStep {
        if let problem = await MainActor.run(body: { problem }) { throw problem }
        if let answer = await MainActor.run(body: { answer }) { await answer() }
        return await MainActor.run {
            let target = movesInstead[channel] ?? channel
            let from = gainDb[target] ?? 0
            var to = min(gainRange.upperBound, max(gainRange.lowerBound, from + gainChangeDb))
            var limit: ReGain.Limit?
            if let ceiling = reGainCeilingDb, to > max(from, ceiling) {
                to = max(from, ceiling)
                limit = Self.gateAtTop
            }
            gainDb[target] = to
            let changes = alsoMoves.map { [$0] } ?? []
            let held = Dictionary(changes.map { ($0.setting, $0.toDb) }, uniquingKeysWith: { _, last in last })
            return GainStep(channel: channel, headamp: target, fromGainDb: from, toGainDb: to, changes: changes, held: held,
                            limitedBy: limit, restore: ["gain/\(target)": Float(from)])
        }
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

    @Test("One channel at -40 dBFS is brought to -18 with its preamp")
    func oneChannel() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        let results = await session.run(usbChannels: [1])

        #expect(results == [.set(usbChannel: 1, channel: 1, fromGainDb: 0, toGainDb: 22, levelDbfs: -18)])
        #expect(control.gainDb[1] == 22)
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

    @Test("Every gain step and every Undo is logged, with what Re-Gain moved (#450)")
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
        control.reGainCeilingDb = 10
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        _ = await session.run(usbChannels: [1])
        _ = await session.run(usbChannels: [1])
        #expect(control.gainDb[1] == 10)
        try await session.undo(usbChannel: 1)

        #expect(control.gainDb[1] == 0)
    }

    @Test("When Re-Gain can't go further, the result says which setting stopped it, not that the preamp ran out")
    func limitNamed() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        control.reGainCeilingDb = 10
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))

        let results = await session.run(usbChannels: [1])

        #expect(results == [.failed(usbChannel: 1, channel: 1, failure: .rangeReached(levelDbfs: -30), limitedBy: FakeGainControl.gateAtTop)])
    }

    @Test("A Re-Gain limit reads as the setting that stopped it and its end stop",
          arguments: [(ReGain.Limit(setting: .init(channel: 1, parameter: .gateThreshold), endDb: 0),
                       "Channel 1's gate threshold is at its end stop (0 dB)"),
                      (ReGain.Limit(setting: .init(channel: 3, parameter: .mainFader), endDb: -90),
                       "Channel 3's fader is at its end stop (-90 dB)"),
                      (ReGain.Limit(setting: .init(channel: 2, parameter: .send(4)), endDb: 10),
                       "Channel 2's send 4 is at its end stop (+10 dB)")])
    func limitText(limit: ReGain.Limit, text: String) {
        #expect(limit.explanation == text)
    }

    @Test("An Undo the Mixer stops answering halfway keeps the steps it didn't undo, and a second Undo finishes the job")
    func undoFailsHalfway() async throws {
        let control = FakeGainControl(gainDb: [1: 0], channelOfUSB: [1: 1])
        let session = AutoGainSession(control: control, measure: Self.meters(control, source: [1: -40]))
        control.reGainCeilingDb = 10
        _ = await session.run(usbChannels: [1])          // 0 -> 10
        control.reGainCeilingDb = 20
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
        control.reGainCeilingDb = 10
        _ = await session.run(usbChannels: [1])          // 0 -> 10
        control.reGainCeilingDb = 20
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
        control.reGainCeilingDb = 0   // the gain can't go up at all
        let fader = ReGain.Setting(channel: 1, parameter: .mainFader)
        control.alsoMoves = ReGain.Change(setting: fader, fromDb: 9.8, toDb: 10)
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
}

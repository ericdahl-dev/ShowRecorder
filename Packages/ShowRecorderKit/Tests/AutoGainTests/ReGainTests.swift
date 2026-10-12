import AutoGain
import Testing

/// Ranges like an X32's: faders and sends to +10 dB, off at -90, the gate threshold -80 to 0, the compressor's -60 to 0.
/// They are data the tests pass in; nothing in the rule knows a Mixer model.
let x32Ranges = ReGain.Ranges(fader: -90...10, send: -90...10, gateThreshold: -80...0, compressorThreshold: -60...0, offDb: -90)

/// A channel with the Mixing Station example's gate (-20) and fader (-15), a compressor, one pre-fader and one
/// post-fader send.
func channel(_ number: Int = 1) -> ReGain.ChannelState {
    ReGain.ChannelState(
        channel: number,
        gateThresholdDb: -20,
        compressorThresholdDb: -30,
        mainFaderDb: -15,
        sends: [ReGain.Send(bus: 1, levelDb: -10, preFader: true), ReGain.Send(bus: 2, levelDb: -5, preFader: false)]
    )
}

@Suite("Re-Gain")
struct ReGainTests {
    @Test("+5 dB of gain raises both thresholds 5 dB and lowers the main fader and pre-fader send 5 dB, as in Mixing Station's example")
    func compensatesUp() {
        let plan = ReGain.plan(headamp: 1, gainChangeDb: 5, channels: [channel()], ranges: x32Ranges)
        #expect(plan.gainChangeDb == 5)
        #expect(Set(plan.changes) == [
            ReGain.Change(setting: .init(channel: 1, parameter: .gateThreshold), fromDb: -20, toDb: -15),
            ReGain.Change(setting: .init(channel: 1, parameter: .compressorThreshold), fromDb: -30, toDb: -25),
            ReGain.Change(setting: .init(channel: 1, parameter: .mainFader), fromDb: -15, toDb: -20),
            ReGain.Change(setting: .init(channel: 1, parameter: .send(1)), fromDb: -10, toDb: -15),
        ])
    }

    @Test("-4 dB of gain moves everything the other way, including other mains such as the X32's mono/center")
    func compensatesDownWithOtherMains() {
        var state = channel()
        state.otherMainsDb = [1: -12]
        let plan = ReGain.plan(headamp: 1, gainChangeDb: -4, channels: [state], ranges: x32Ranges)
        #expect(Set(plan.changes) == [
            ReGain.Change(setting: .init(channel: 1, parameter: .gateThreshold), fromDb: -20, toDb: -24),
            ReGain.Change(setting: .init(channel: 1, parameter: .compressorThreshold), fromDb: -30, toDb: -34),
            ReGain.Change(setting: .init(channel: 1, parameter: .mainFader), fromDb: -15, toDb: -11),
            ReGain.Change(setting: .init(channel: 1, parameter: .otherMain(1)), fromDb: -12, toDb: -8),
            ReGain.Change(setting: .init(channel: 1, parameter: .send(1)), fromDb: -10, toDb: -6),
        ])
    }

    @Test("Sends and faders at or below -90 dB are off and left alone, so lowering the gain never opens them")
    func offIsUntouched() {
        var state = channel()
        state.mainFaderDb = -90
        state.sends = [ReGain.Send(bus: 1, levelDb: -90, preFader: true), ReGain.Send(bus: 3, levelDb: -89.5, preFader: true)]
        let plan = ReGain.plan(headamp: 1, gainChangeDb: -4, channels: [state], ranges: x32Ranges)
        let touched = Set(plan.changes.map(\.setting.parameter))
        #expect(touched == [.gateThreshold, .compressorThreshold, .send(3)])
    }

    @Test("Post-fader sends are never in the plan: they follow the fader")
    func postFaderUntouched() {
        let plan = ReGain.plan(headamp: 1, gainChangeDb: 3, channels: [channel()], ranges: x32Ranges)
        #expect(!plan.changes.contains { $0.setting.parameter == .send(2) })
    }

    @Test("Each scope can be turned off, like Re-Gain's Sends, Gate, Compressor, LR and Other mains switches", arguments: [
        (ReGain.Scopes.sends, ReGain.Parameter.send(1)),
        (.gate, .gateThreshold),
        (.compressor, .compressorThreshold),
        (.mainLR, .mainFader),
        (.otherMains, .otherMain(1)),
    ])
    func scopeOff(scope: ReGain.Scopes, parameter: ReGain.Parameter) {
        var state = channel()
        state.otherMainsDb = [1: -12]
        let all = ReGain.plan(headamp: 1, gainChangeDb: 3, channels: [state], ranges: x32Ranges)
        let without = ReGain.plan(headamp: 1, gainChangeDb: 3, channels: [state], ranges: x32Ranges, scopes: ReGain.Scopes.all.subtracting(scope))
        #expect(all.changes.contains { $0.setting.parameter == parameter })
        #expect(!without.changes.contains { $0.setting.parameter == parameter })
        #expect(without.changes.count == all.changes.count - 1)
    }

    @Test("Lowering the gain is limited by a main fader near +10 dB, and the plan says which fader stopped it")
    func limitedByFader() {
        var state = channel()
        state.mainFaderDb = 8
        let plan = ReGain.plan(headamp: 1, gainChangeDb: -6, channels: [state], ranges: x32Ranges)
        #expect(plan.requestedDb == -6)
        #expect(plan.gainChangeDb == -2)
        #expect(plan.limitedBy == ReGain.Limit(setting: .init(channel: 1, parameter: .mainFader), endDb: 10))
        #expect(plan.changes.contains(ReGain.Change(setting: .init(channel: 1, parameter: .mainFader), fromDb: 8, toDb: 10)))
    }

    @Test("The compensable range runs from whichever setting runs out first in each direction (Re-Gain's red lines)")
    func compensableRange() {
        var state = channel()
        state.gateThresholdDb = -2
        state.sends = [ReGain.Send(bus: 1, levelDb: -86, preFader: true)]
        let range = ReGain.compensableRange(channels: [state], ranges: x32Ranges)
        // Up: the gate threshold reaches 0 after 2 dB (the send would reach -90 only after 4).
        #expect(range.highestDb == 2)
        #expect(range.upperLimit == ReGain.Limit(setting: .init(channel: 1, parameter: .gateThreshold), endDb: 0))
        // Down: the main fader reaches +10 after 25 dB.
        #expect(range.lowestDb == -25)
        #expect(range.lowerLimit == ReGain.Limit(setting: .init(channel: 1, parameter: .mainFader), endDb: 10))

        let plan = ReGain.plan(headamp: 1, gainChangeDb: 5, channels: [state], ranges: x32Ranges)
        #expect(plan.gainChangeDb == 2)
        #expect(plan.limitedBy == range.upperLimit)
    }

    @Test("A send at its maximum stops the gain going down at all")
    func sendAtMax() {
        var state = channel()
        state.sends = [ReGain.Send(bus: 4, levelDb: 10, preFader: true)]
        let plan = ReGain.plan(headamp: 1, gainChangeDb: -3, channels: [state], ranges: x32Ranges)
        #expect(plan.gainChangeDb == 0)
        #expect(plan.limitedBy == ReGain.Limit(setting: .init(channel: 1, parameter: .send(4)), endDb: 10))
    }

    @Test("Within the range nothing is limited")
    func notLimited() {
        let plan = ReGain.plan(headamp: 1, gainChangeDb: 5, channels: [channel()], ranges: x32Ranges)
        #expect(plan.limitedBy == nil)
    }

    @Test("A stereo-linked pair moves together: either channel's headamp brings in both")
    func linkedPair() {
        let sources = [
            ReGain.ChannelSource(channel: 1, headamp: 1, linkedChannel: 2),
            ReGain.ChannelSource(channel: 2, headamp: 2, linkedChannel: 1),
            ReGain.ChannelSource(channel: 3, headamp: 3),
        ]
        #expect(ReGain.channels(movedByHeadamp: 1, sources: sources) == [1, 2])
        #expect(ReGain.channels(movedByHeadamp: 2, sources: sources) == [1, 2])
        #expect(ReGain.channels(movedByHeadamp: 3, sources: sources) == [3])
    }

    @Test("An X32 headamp feeding two channels compensates both, and the range is the tighter of the two")
    func headampFeedingTwo() {
        let sources = [
            ReGain.ChannelSource(channel: 3, headamp: 5),
            ReGain.ChannelSource(channel: 9, headamp: 5),
            ReGain.ChannelSource(channel: 4, headamp: 6),
        ]
        #expect(ReGain.channels(movedByHeadamp: 5, sources: sources) == [3, 9])

        var other = channel(9)
        other.mainFaderDb = 7
        let plan = ReGain.plan(headamp: 5, gainChangeDb: -5, channels: [channel(3), other], ranges: x32Ranges)
        #expect(plan.gainChangeDb == -3)
        #expect(plan.limitedBy?.setting == .init(channel: 9, parameter: .mainFader))
        #expect(plan.changes.contains(ReGain.Change(setting: .init(channel: 3, parameter: .mainFader), fromDb: -15, toDb: -12)))
        #expect(plan.changes.contains(ReGain.Change(setting: .init(channel: 9, parameter: .mainFader), fromDb: 7, toDb: 10)))
    }

    @Test("The undo set holds the before-values, so it restores every compensated setting exactly, and the gain move to reverse")
    func undoRestores() {
        var state = channel()
        state.mainFaderDb = -15.3
        let before = [state]
        let plan = ReGain.plan(headamp: 1, gainChangeDb: 4.7, channels: before, ranges: x32Ranges)
        let after = ReGain.apply(plan.values, to: before)
        #expect(after != before)
        #expect(ReGain.apply(plan.undo.beforeDb, to: after) == before)
        #expect(plan.undo.gainMovedDb == [1: 4.7])
    }

    @Test("Undo sets combine over a run: the first before-value of each setting wins, and each headamp's moves add up")
    func undoCombines() {
        // Two steps of the loop on channel 1 (headamp 1), and one on channel 2 (headamp 2), all in one run.
        let original = [channel(1), channel(2)]
        let first = ReGain.plan(headamp: 1, gainChangeDb: 6, channels: [original[0]], ranges: x32Ranges)
        let afterFirst = ReGain.apply(first.values, to: original)
        let second = ReGain.plan(headamp: 1, gainChangeDb: -2, channels: [afterFirst[0]], ranges: x32Ranges)
        let afterSecond = ReGain.apply(second.values, to: afterFirst)
        let third = ReGain.plan(headamp: 2, gainChangeDb: 3, channels: [afterSecond[1]], ranges: x32Ranges)
        let end = ReGain.apply(third.values, to: afterSecond)

        var run = ReGain.UndoSet()
        run.merge(first.undo)
        run.merge(second.undo)
        run.merge(third.undo)
        #expect(ReGain.apply(run.beforeDb, to: end) == original)
        #expect(run.gainMovedDb == [1: 4, 2: 3])
    }

    @Test("A threshold on another channel keyed from a moved channel moves +g too, with an undo before-value")
    func sidechainCompensated() {
        let keyed = [
            ReGain.KeyedDynamics(channel: 5, dynamics: .compressor, thresholdDb: -25, keyChannel: 1),
            // Keyed from a channel that isn't moving: untouched.
            ReGain.KeyedDynamics(channel: 6, dynamics: .gate, thresholdDb: -40, keyChannel: 2),
        ]
        let plan = ReGain.plan(headamp: 1, gainChangeDb: 3, channels: [channel(1)], ranges: x32Ranges, keyed: keyed)
        let setting = ReGain.Setting(channel: 5, parameter: .compressorThreshold)
        #expect(plan.changes.contains(ReGain.Change(setting: setting, fromDb: -25, toDb: -22)))
        #expect(plan.values[setting] == -22)
        #expect(plan.undo.beforeDb[setting] == -25)
        #expect(!plan.changes.contains { $0.setting.channel == 6 })
    }

    @Test("A keyed threshold near its top limits the compensable range, and the limit names it")
    func sidechainLimits() {
        let keyed = [ReGain.KeyedDynamics(channel: 5, dynamics: .gate, thresholdDb: -1, keyChannel: 1)]
        let setting = ReGain.Setting(channel: 5, parameter: .gateThreshold)
        let range = ReGain.compensableRange(channels: [channel(1)], keyed: keyed, ranges: x32Ranges)
        #expect(range.highestDb == 1)
        #expect(range.upperLimit == ReGain.Limit(setting: setting, endDb: 0))

        let plan = ReGain.plan(headamp: 1, gainChangeDb: 4, channels: [channel(1)], ranges: x32Ranges, keyed: keyed)
        #expect(plan.gainChangeDb == 1)
        #expect(plan.limitedBy == ReGain.Limit(setting: setting, endDb: 0))
    }

    @Test("Keyed thresholds follow the Gate and Compressor switches")
    func sidechainScoped() {
        let keyed = [
            ReGain.KeyedDynamics(channel: 5, dynamics: .gate, thresholdDb: -40, keyChannel: 1),
            ReGain.KeyedDynamics(channel: 6, dynamics: .compressor, thresholdDb: -25, keyChannel: 1),
        ]
        let noGate = ReGain.plan(headamp: 1, gainChangeDb: 3, channels: [channel(1)], ranges: x32Ranges, scopes: [.compressor], keyed: keyed)
        #expect(noGate.changes.map(\.setting) == [.init(channel: 1, parameter: .compressorThreshold), .init(channel: 6, parameter: .compressorThreshold)])
        let noCompressor = ReGain.plan(headamp: 1, gainChangeDb: 3, channels: [channel(1)], ranges: x32Ranges, scopes: [.gate], keyed: keyed)
        #expect(noCompressor.changes.map(\.setting) == [.init(channel: 1, parameter: .gateThreshold), .init(channel: 5, parameter: .gateThreshold)])
    }

    @Test("Dynamics keyed within the moved channels are compensated once, as those channels' own thresholds")
    func sidechainWithinGroup() {
        // Channel 2 is linked with channel 1, and its gate is keyed from channel 1.
        let keyed = [ReGain.KeyedDynamics(channel: 2, dynamics: .gate, thresholdDb: -20, keyChannel: 1)]
        let plan = ReGain.plan(headamp: 1, gainChangeDb: 3, channels: [channel(1), channel(2)], ranges: x32Ranges, keyed: keyed)
        #expect(plan.changes.filter { $0.setting == .init(channel: 2, parameter: .gateThreshold) }.count == 1)
    }
}

/// A Mixer with one channel behind headamp 1 and a steady source: the recorded level follows the gain dB for dB.
/// The gain is private, as on the EVO; only the channel's other settings can be read.
final class FakeMixer {
    private var gainDb: Double
    let sourceDbfs: Double
    var state: ReGain.ChannelState
    private(set) var gainWrites: [Double] = []

    init(gainDb: Double, sourceDbfs: Double, state: ReGain.ChannelState) {
        self.gainDb = gainDb
        self.sourceDbfs = sourceDbfs
        self.state = state
    }

    var levelDbfs: Double { min(sourceDbfs + gainDb, 0) }

    /// Writes a gain move and its compensation together, as #153 and #392 would.
    func write(gainMoveDb: Double, values: [ReGain.Setting: Double]) {
        gainDb += gainMoveDb
        gainWrites.append(gainMoveDb)
        state = ReGain.apply(values, to: [state])[0]
    }
}

@Suite("Re-Gain in the auto-gain loop")
struct ReGainLoopTests {
    @Test("Each step is limited to the compensable range, the reason is kept, and one undo set restores the whole run")
    func loopLimitedByCompensation() async throws {
        var start = channel()
        start.mainFaderDb = 2
        let mixer = FakeMixer(gainDb: 30, sourceDbfs: -40, state: start)
        var run = ReGain.Run(ranges: x32Ranges)

        let outcome = try await AutoGainRule().run(
            measure: { mixer.levelDbfs },
            adjust: { requested in
                // Read fresh before every step, never cached.
                let plan = run.step(headamp: 1, gainChangeDb: requested, channels: [mixer.state])
                mixer.write(gainMoveDb: plan.gainChangeDb, values: plan.values)
                return plan.gainChangeDb
            },
            settle: {}
        )

        // -10 dBFS wants 8 dB less gain; the fader at +2 can only rise 8 dB to +10, so the first step is all of it...
        #expect(outcome == .onTarget(levelDbfs: -18, changeDb: -8, passes: 1))
        #expect(mixer.state.mainFaderDb == 10)
        #expect(run.limitedBy == nil)

        // ...and asking for more is limited to nothing, with the fader as the reason.
        let more = run.step(headamp: 1, gainChangeDb: -3, channels: [mixer.state])
        #expect(more.gainChangeDb == 0)
        #expect(run.limitedBy == ReGain.Limit(setting: .init(channel: 1, parameter: .mainFader), endDb: 10))

        mixer.write(gainMoveDb: -(run.undo.gainMovedDb[1] ?? 0), values: run.undo.beforeDb)
        #expect(mixer.state == start)
        #expect(mixer.levelDbfs == -10)
    }

    @Test("A fader at its end stops the loop with range reached")
    func loopStopsAtTheEnd() async throws {
        var start = channel()
        start.mainFaderDb = 10
        let mixer = FakeMixer(gainDb: 30, sourceDbfs: -40, state: start)
        var run = ReGain.Run(ranges: x32Ranges)
        let outcome = try await AutoGainRule().run(
            measure: { mixer.levelDbfs },
            adjust: { requested in
                let plan = run.step(headamp: 1, gainChangeDb: requested, channels: [mixer.state])
                mixer.write(gainMoveDb: plan.gainChangeDb, values: plan.values)
                return plan.gainChangeDb
            },
            settle: {}
        )
        #expect(outcome == .failed(.rangeReached(levelDbfs: -10), changeDb: 0))
        #expect(run.limitedBy?.setting.parameter == .mainFader)
        #expect(mixer.state == start)
    }
}

import AutoGain
import Testing

/// Ranges like an X32's: faders and sends to +10 dB, off at -90, the gate threshold -80 to 0, the compressor's -60 to 0.
/// They are data the tests pass in; nothing in the rule knows a Mixer model.
let x32Ranges = MixHold.Ranges(fader: -90...10, send: -90...10, gateThreshold: -80...0, compressorThreshold: -60...0, offDb: -90)

/// A channel with a gate at -20 and the fader at -15, a compressor, one pre-fader and one
/// post-fader send.
func channel(_ number: Int = 1) -> MixHold.ChannelState {
    MixHold.ChannelState(
        channel: number,
        gateThresholdDb: -20,
        compressorThresholdDb: -30,
        mainFaderDb: -15,
        sends: [MixHold.Send(bus: 1, levelDb: -10, preFader: true), MixHold.Send(bus: 2, levelDb: -5, preFader: false)]
    )
}

@Suite("Mix Hold")
struct MixHoldTests {
    @Test("+5 dB of gain raises both thresholds 5 dB and lowers the main fader and pre-fader send 5 dB")
    func compensatesUp() {
        let plan = MixHold.plan(headamp: 1, gainChangeDb: 5, channels: [channel()], ranges: x32Ranges)
        #expect(plan.gainChangeDb == 5)
        #expect(Set(plan.changes) == [
            MixHold.Change(setting: .init(channel: 1, parameter: .gateThreshold), fromDb: -20, toDb: -15),
            MixHold.Change(setting: .init(channel: 1, parameter: .compressorThreshold), fromDb: -30, toDb: -25),
            MixHold.Change(setting: .init(channel: 1, parameter: .mainFader), fromDb: -15, toDb: -20),
            MixHold.Change(setting: .init(channel: 1, parameter: .send(1)), fromDb: -10, toDb: -15),
        ])
    }

    @Test("-4 dB of gain moves everything the other way, including other mains such as the X32's mono/center")
    func compensatesDownWithOtherMains() {
        var state = channel()
        state.otherMainsDb = [1: -12]
        let plan = MixHold.plan(headamp: 1, gainChangeDb: -4, channels: [state], ranges: x32Ranges)
        #expect(Set(plan.changes) == [
            MixHold.Change(setting: .init(channel: 1, parameter: .gateThreshold), fromDb: -20, toDb: -24),
            MixHold.Change(setting: .init(channel: 1, parameter: .compressorThreshold), fromDb: -30, toDb: -34),
            MixHold.Change(setting: .init(channel: 1, parameter: .mainFader), fromDb: -15, toDb: -11),
            MixHold.Change(setting: .init(channel: 1, parameter: .otherMain(1)), fromDb: -12, toDb: -8),
            MixHold.Change(setting: .init(channel: 1, parameter: .send(1)), fromDb: -10, toDb: -6),
        ])
    }

    @Test("Sends and faders at or below -90 dB are off and left alone, so lowering the gain never opens them")
    func offIsUntouched() {
        var state = channel()
        state.mainFaderDb = -90
        state.sends = [MixHold.Send(bus: 1, levelDb: -90, preFader: true), MixHold.Send(bus: 3, levelDb: -89.5, preFader: true)]
        let plan = MixHold.plan(headamp: 1, gainChangeDb: -4, channels: [state], ranges: x32Ranges)
        let touched = Set(plan.changes.map(\.setting.parameter))
        #expect(touched == [.gateThreshold, .compressorThreshold, .send(3)])
    }

    @Test("Post-fader sends are never in the plan: they follow the fader")
    func postFaderUntouched() {
        let plan = MixHold.plan(headamp: 1, gainChangeDb: 3, channels: [channel()], ranges: x32Ranges)
        #expect(!plan.changes.contains { $0.setting.parameter == .send(2) })
    }

    @Test("Each scope can be turned off, like Mix Hold's Sends, Gate, Compressor, LR and Other mains switches", arguments: [
        (MixHold.Scopes.sends, MixHold.Parameter.send(1)),
        (.gate, .gateThreshold),
        (.compressor, .compressorThreshold),
        (.mainLR, .mainFader),
        (.otherMains, .otherMain(1)),
    ])
    func scopeOff(scope: MixHold.Scopes, parameter: MixHold.Parameter) {
        for gain in [3.0, -3.0] {   // both ways (#393)
            scopeOff(scope: scope, parameter: parameter, gainChangeDb: gain)
        }
    }

    func scopeOff(scope: MixHold.Scopes, parameter: MixHold.Parameter, gainChangeDb: Double) {
        var state = channel()
        state.otherMainsDb = [1: -12]
        let all = MixHold.plan(headamp: 1, gainChangeDb: gainChangeDb, channels: [state], ranges: x32Ranges)
        let without = MixHold.plan(headamp: 1, gainChangeDb: gainChangeDb, channels: [state], ranges: x32Ranges,
                                  scopes: MixHold.Scopes.all.subtracting(scope))
        #expect(all.changes.contains { $0.setting.parameter == parameter })
        #expect(!without.changes.contains { $0.setting.parameter == parameter })
        #expect(without.changes.count == all.changes.count - 1)
    }

    @Test("Lowering the gain is limited by a main fader near +10 dB, and the plan says which fader stopped it")
    func limitedByFader() {
        var state = channel()
        state.mainFaderDb = 8
        let plan = MixHold.plan(headamp: 1, gainChangeDb: -6, channels: [state], ranges: x32Ranges)
        #expect(plan.requestedDb == -6)
        #expect(plan.gainChangeDb == -2)
        #expect(plan.limitedBy == MixHold.Limit(setting: .init(channel: 1, parameter: .mainFader), endDb: 10))
        #expect(plan.changes.contains(MixHold.Change(setting: .init(channel: 1, parameter: .mainFader), fromDb: 8, toDb: 10)))
    }

    @Test("The compensable range runs from whichever setting runs out first in each direction (Mix Hold's red lines)")
    func compensableRange() {
        var state = channel()
        state.gateThresholdDb = -2
        state.sends = [MixHold.Send(bus: 1, levelDb: -86, preFader: true)]
        let range = MixHold.compensableRange(channels: [state], ranges: x32Ranges)
        // Up: the gate threshold reaches 0 after 2 dB (the send would reach -90 only after 4).
        #expect(range.highestDb == 2)
        #expect(range.upperLimit == MixHold.Limit(setting: .init(channel: 1, parameter: .gateThreshold), endDb: 0))
        // Down: the main fader reaches +10 after 25 dB.
        #expect(range.lowestDb == -25)
        #expect(range.lowerLimit == MixHold.Limit(setting: .init(channel: 1, parameter: .mainFader), endDb: 10))

        let plan = MixHold.plan(headamp: 1, gainChangeDb: 5, channels: [state], ranges: x32Ranges)
        #expect(plan.gainChangeDb == 2)
        #expect(plan.limitedBy == range.upperLimit)
    }

    @Test("A send at its maximum stops the gain going down at all")
    func sendAtMax() {
        var state = channel()
        state.sends = [MixHold.Send(bus: 4, levelDb: 10, preFader: true)]
        let plan = MixHold.plan(headamp: 1, gainChangeDb: -3, channels: [state], ranges: x32Ranges)
        #expect(plan.gainChangeDb == 0)
        #expect(plan.limitedBy == MixHold.Limit(setting: .init(channel: 1, parameter: .send(4)), endDb: 10))
    }

    @Test("Within the range nothing is limited")
    func notLimited() {
        let plan = MixHold.plan(headamp: 1, gainChangeDb: 5, channels: [channel()], ranges: x32Ranges)
        #expect(plan.limitedBy == nil)
    }

    @Test("An X32 headamp feeding two channels compensates both, and the range is the tighter of the two")
    func headampFeedingTwo() {
        var other = channel(9)
        other.mainFaderDb = 7
        let plan = MixHold.plan(headamp: 5, gainChangeDb: -5, channels: [channel(3), other], ranges: x32Ranges)
        #expect(plan.gainChangeDb == -3)
        #expect(plan.limitedBy?.setting == .init(channel: 9, parameter: .mainFader))
        #expect(plan.changes.contains(MixHold.Change(setting: .init(channel: 3, parameter: .mainFader), fromDb: -15, toDb: -12)))
        #expect(plan.changes.contains(MixHold.Change(setting: .init(channel: 9, parameter: .mainFader), fromDb: 7, toDb: 10)))
    }

    @Test("A threshold on another channel keyed from a moved channel moves +g too")
    func sidechainCompensated() {
        let keyed = [
            MixHold.KeyedDynamics(channel: 5, dynamics: .compressor, thresholdDb: -25, keyChannel: 1),
            // Keyed from a channel that isn't moving: untouched.
            MixHold.KeyedDynamics(channel: 6, dynamics: .gate, thresholdDb: -40, keyChannel: 2),
        ]
        let plan = MixHold.plan(headamp: 1, gainChangeDb: 3, channels: [channel(1)], ranges: x32Ranges, keyed: keyed)
        let setting = MixHold.Setting(channel: 5, parameter: .compressorThreshold)
        #expect(plan.changes.contains(MixHold.Change(setting: setting, fromDb: -25, toDb: -22)))
        #expect(plan.values[setting] == -22)
        #expect(!plan.changes.contains { $0.setting.channel == 6 })
    }

    @Test("A keyed threshold near its top limits the compensable range, and the limit names it")
    func sidechainLimits() {
        let keyed = [MixHold.KeyedDynamics(channel: 5, dynamics: .gate, thresholdDb: -1, keyChannel: 1)]
        let setting = MixHold.Setting(channel: 5, parameter: .gateThreshold)
        let range = MixHold.compensableRange(channels: [channel(1)], keyed: keyed, ranges: x32Ranges)
        #expect(range.highestDb == 1)
        #expect(range.upperLimit == MixHold.Limit(setting: setting, endDb: 0))

        let plan = MixHold.plan(headamp: 1, gainChangeDb: 4, channels: [channel(1)], ranges: x32Ranges, keyed: keyed)
        #expect(plan.gainChangeDb == 1)
        #expect(plan.limitedBy == MixHold.Limit(setting: setting, endDb: 0))
    }

    @Test("Keyed thresholds follow the Gate and Compressor switches")
    func sidechainScoped() {
        let keyed = [
            MixHold.KeyedDynamics(channel: 5, dynamics: .gate, thresholdDb: -40, keyChannel: 1),
            MixHold.KeyedDynamics(channel: 6, dynamics: .compressor, thresholdDb: -25, keyChannel: 1),
        ]
        let noGate = MixHold.plan(headamp: 1, gainChangeDb: 3, channels: [channel(1)], ranges: x32Ranges, scopes: [.compressor], keyed: keyed)
        #expect(noGate.changes.map(\.setting) == [.init(channel: 1, parameter: .compressorThreshold), .init(channel: 6, parameter: .compressorThreshold)])
        let noCompressor = MixHold.plan(headamp: 1, gainChangeDb: 3, channels: [channel(1)], ranges: x32Ranges, scopes: [.gate], keyed: keyed)
        #expect(noCompressor.changes.map(\.setting) == [.init(channel: 1, parameter: .gateThreshold), .init(channel: 5, parameter: .gateThreshold)])
    }

    @Test("Dynamics keyed within the moved channels are compensated once, as those channels' own thresholds")
    func sidechainWithinGroup() {
        // Channel 2 is linked with channel 1, and its gate is keyed from channel 1.
        let keyed = [MixHold.KeyedDynamics(channel: 2, dynamics: .gate, thresholdDb: -20, keyChannel: 1)]
        let plan = MixHold.plan(headamp: 1, gainChangeDb: 3, channels: [channel(1), channel(2)], ranges: x32Ranges, keyed: keyed)
        #expect(plan.changes.filter { $0.setting == .init(channel: 2, parameter: .gateThreshold) }.count == 1)
    }
}

@Suite("Mix Hold in the auto-gain loop")
struct MixHoldLoopTests {
    @Test("A gate keyed from an input two moved channels share is compensated once, not once per channel (#473)")
    func keyedOncePerSetting() {
        let ranges = MixHold.Ranges(fader: -90...10, send: -90...10, gateThreshold: -80...0, compressorThreshold: -60...0, offDb: -90)
        let keyed = [1, 17].map { MixHold.KeyedDynamics(channel: 5, dynamics: .gate, thresholdDb: -40, keyChannel: $0) }
        let plan = MixHold.plan(headamp: 0, gainChangeDb: 6, channels: [MixHold.ChannelState(channel: 1), MixHold.ChannelState(channel: 17)],
                               ranges: ranges, keyed: keyed)
        #expect(plan.changes == [MixHold.Change(setting: MixHold.Setting(channel: 5, parameter: .gateThreshold), fromDb: -40, toDb: -34)])
    }

    @Test("Each end stop limits the gain the way it runs out: compressor top on a boost, gate and compressor bottoms on a cut, a send near off on a boost (#393)",
          arguments: [
            (MixHold.Parameter.compressorThreshold, -2.0, 5.0, 2.0, 0.0),
            (.gateThreshold, -78.0, -5.0, -2.0, -80.0),
            (.compressorThreshold, -58.0, -5.0, -2.0, -60.0),
            (.send(1), -86.0, 5.0, 4.0, -90.0),
          ])
    func endStops(parameter: MixHold.Parameter, valueDb: Double, requestDb: Double, allowedDb: Double, endDb: Double) {
        var state = channel()
        switch parameter {
        case .gateThreshold: state.gateThresholdDb = valueDb
        case .compressorThreshold: state.compressorThresholdDb = valueDb
        case .send(let bus): state.sends = [MixHold.Send(bus: bus, levelDb: valueDb, preFader: true)]
        default: Issue.record("not covered")
        }
        let plan = MixHold.plan(headamp: 1, gainChangeDb: requestDb, channels: [state], ranges: x32Ranges)
        #expect(plan.gainChangeDb == allowedDb)
        #expect(plan.limitedBy == MixHold.Limit(setting: .init(channel: 1, parameter: parameter), endDb: endDb))
    }
    @Test("A gate or compressor keyed from another channel hears that channel, not this preamp: its threshold stays (#497)")
    func keyedElsewhereStays() {
        var state = channel(2)
        state.compressorKey = .channel(1)
        state.gateKey = .elsewhere   // a bus, say
        let plan = MixHold.plan(headamp: 2, gainChangeDb: 5, channels: [state], ranges: x32Ranges)
        #expect(!plan.changes.contains { $0.setting.parameter == .compressorThreshold })
        #expect(!plan.changes.contains { $0.setting.parameter == .gateThreshold })
        #expect(plan.changes.contains { $0.setting.parameter == .mainFader }, "the rest still moves")
    }

    @Test("Keyed from a channel that moves with it (a stereo-linked partner on one preamp), the threshold moves once")
    func keyedFromPartnerMoves() {
        var partner = channel(2)
        partner.compressorKey = .channel(1)
        let plan = MixHold.plan(headamp: 1, gainChangeDb: 5, channels: [channel(1), partner], ranges: x32Ranges)
        #expect(plan.changes.filter { $0.setting == .init(channel: 2, parameter: .compressorThreshold) }
                == [MixHold.Change(setting: .init(channel: 2, parameter: .compressorThreshold), fromDb: -30, toDb: -25)])
    }

    @Test("Channel 2's compressor keyed from channel 1: moving each preamp in turn moves that threshold once, with channel 1 (#497)")
    func keyedThresholdMovedByOneChannelOnly() {
        var two = channel(2)
        two.compressorKey = .channel(1)
        let keyed = [MixHold.KeyedDynamics(channel: 2, dynamics: .compressor, thresholdDb: -30, keyChannel: 1)]
        let first = MixHold.plan(headamp: 1, gainChangeDb: 5, channels: [channel(1)], ranges: x32Ranges, keyed: keyed)
        let second = MixHold.plan(headamp: 2, gainChangeDb: 3, channels: [two], ranges: x32Ranges)
        let threshold = MixHold.Setting(channel: 2, parameter: .compressorThreshold)
        #expect(first.changes.contains { $0.setting == threshold })
        #expect(!second.changes.contains { $0.setting == threshold }, "so undoing either never undoes the other's")
    }
    @Test("Keyed from an input (the X32 keys from a source): it moves when a channel moving with this preamp takes that input")
    func keyedFromSource() {
        var one = channel(1)
        one.source = 1
        var nine = channel(9)
        nine.source = 9
        nine.gateKey = .source(1)   // In01, which channel 1 takes, on the same headamp
        var alone = channel(9)
        alone.gateKey = .source(1)
        let gate = MixHold.Setting(channel: 9, parameter: .gateThreshold)
        #expect(MixHold.plan(headamp: 1, gainChangeDb: 5, channels: [one, nine], ranges: x32Ranges).changes.contains { $0.setting == gate })
        #expect(!MixHold.plan(headamp: 9, gainChangeDb: 5, channels: [alone], ranges: x32Ranges).changes.contains { $0.setting == gate })
    }
}

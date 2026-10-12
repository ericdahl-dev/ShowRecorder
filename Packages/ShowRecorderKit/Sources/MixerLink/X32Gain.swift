import AutoGain
import OSC

/// Preamp gain on an X32, and the settings Re-Gain compensates (#392). Values follow `X32Values`.
extension X32Driver {
    /// The preamp (headamp 0–127) behind input channel `channel` (1–32), as the X32 reports it (`/-ha/NN/index`): 0–31
    /// local inputs, 32–79 AES50 A, 80–127 AES50 B. Nil when the channel has none, such as a card or USB source.
    public func headamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? {
        let index = Int(try await queries.int(at: String(format: "/-ha/%02d/index", channel - 1)))
        return (0...127).contains(index) ? index : nil
    }

    /// What Re-Gain needs to know about input channel `channel` (1–32), read fresh: gate and compressor thresholds, the
    /// fader (main LR), the mono/center level (other main 1), and its 16 bus sends. A send's pre or post comes from its
    /// pair's type (set on the odd send): IN/LC, <-EQ, EQ-> and PRE are before the fader, POST and GRP after it.
    public func reGainState(ofChannel channel: Int) async throws(MixerLinkProblem) -> ReGain.ChannelState {
        let base = String(format: "/ch/%02d", channel)
        let gate = X32Values.gateThreshold.db(ofOSC: try await queries.float(at: base + "/gate/thr"))
        let compressor = X32Values.compressorThreshold.db(ofOSC: try await queries.float(at: base + "/dyn/thr"))
        let fader = X32Values.fader.db(ofOSC: try await queries.float(at: base + "/mix/fader"))
        let mono = X32Values.level.db(ofOSC: try await queries.float(at: base + "/mix/mlevel"))
        var sends: [ReGain.Send] = []
        var preFader = false
        for bus in 1...16 {
            let address = String(format: "%@/mix/%02d", base, bus)
            if bus % 2 == 1 { preFader = try await queries.int(at: address + "/type") <= 3 }
            let level = X32Values.level.db(ofOSC: try await queries.float(at: address + "/level"))
            sends.append(ReGain.Send(bus: bus, levelDb: level, preFader: preFader))
        }
        return ReGain.ChannelState(channel: channel, gateThresholdDb: gate, compressorThresholdDb: compressor,
                                   mainFaderDb: fader, otherMainsDb: [1: mono], sends: sends)
    }

    /// Gates and compressors on other channels whose key source is `channel`'s input, read fresh. The X32 keys from a
    /// source, not a channel: key 1–64 is the same list as a channel's source (In01…, aux, USB, FX, buses), and 0 is
    /// the channel's own signal. A channel with no source (off) keys nothing.
    public func keyedDynamics(from channel: Int) async throws(MixerLinkProblem) -> [ReGain.KeyedDynamics] {
        let source = Int(try await queries.int(at: String(format: "/ch/%02d/config/source", channel)))
        guard (1...64).contains(source) else { return [] }
        var keyed: [ReGain.KeyedDynamics] = []
        for other in 1...32 where other != channel {
            let base = String(format: "/ch/%02d", other)
            if Int(try await queries.int(at: base + "/gate/keysrc")) == source {
                let threshold = X32Values.gateThreshold.db(ofOSC: try await queries.float(at: base + "/gate/thr"))
                keyed.append(ReGain.KeyedDynamics(channel: other, dynamics: .gate, thresholdDb: threshold, keyChannel: channel))
            }
            if Int(try await queries.int(at: base + "/dyn/keysrc")) == source {
                let threshold = X32Values.compressorThreshold.db(ofOSC: try await queries.float(at: base + "/dyn/thr"))
                keyed.append(ReGain.KeyedDynamics(channel: other, dynamics: .compressor, thresholdDb: threshold, keyChannel: channel))
            }
        }
        return keyed
    }

    /// The gain of preamp `headamp` (0–127), in dB.
    public func gainDb(ofHeadamp headamp: Int) async throws(MixerLinkProblem) -> Double {
        X32Values.headampGain.db(ofOSC: try await queries.float(at: Self.gainAddress(headamp)))
    }

    /// Moves input channel `channel`'s preamp by `gainChangeDb` and compensates everything after it with Re-Gain
    /// (#393), so the mix stays the same and only the recorded level moves. Everything is read fresh first.
    ///
    /// The gain stops at the preamp's range (-12…+60 dB) and at what Re-Gain can compensate (`plan.limitedBy`), and
    /// every value is written on one of the X32's own steps: `held` is what the X32 holds afterwards, which can differ
    /// from the plan by up to half a step. Never call it during a Take (#155 doesn't offer it then).
    public func applyReGain(channel: Int, gainChangeDb: Double, scopes: ReGain.Scopes = .all) async throws(MixerLinkProblem) -> X32ReGain {
        guard let headamp = try await headamp(ofChannel: channel) else { throw .noPreamp(channel: channel) }
        let from = try await gainDb(ofHeadamp: headamp)
        let reachable = X32Values.headampGain.snap(from + gainChangeDb) - from
        let state = try await reGainState(ofChannel: channel)
        let keyed = try await keyedDynamics(from: channel)
        let ranges = ReGain.Ranges(fader: -90...10, send: -90...10, gateThreshold: -80...0, compressorThreshold: -60...0, offDb: -90)
        let plan = ReGain.plan(headamp: headamp, gainChangeDb: reachable, channels: [state], ranges: ranges, scopes: scopes, keyed: keyed)
        let to = X32Values.headampGain.snap(from + plan.gainChangeDb)

        // The raw value of every address about to change, so undo restores it exactly.
        var addresses = [Self.gainAddress(headamp)]
        addresses += plan.values.keys.map { Self.address(of: $0) }
        var restore: [String: Float] = [:]
        for address in addresses { restore[address] = try await queries.float(at: address) }

        await client.send(OSCMessage(Self.gainAddress(headamp), [.float(X32Values.headampGain.oscFloat(to))]))
        var held: [ReGain.Setting: Double] = [:]
        for (setting, db) in plan.values {
            let scale = Self.scale(of: setting.parameter)
            await client.send(OSCMessage(Self.address(of: setting), [.float(scale.oscFloat(db))]))
            held[setting] = scale.snap(db)
        }
        return X32ReGain(channel: channel, headamp: headamp, fromGainDb: from, toGainDb: to, plan: plan, held: held, restore: restore)
    }

    /// Puts back every value `result` changed, exactly as it was read before.
    public func undo(_ result: X32ReGain) async throws(MixerLinkProblem) {
        for (address, value) in result.restore {
            await client.send(OSCMessage(address, [.float(value)]))
        }
        _ = try await identify()   // the X32 answers, so the writes reached it
    }

    static func gainAddress(_ headamp: Int) -> String { String(format: "/headamp/%03d/gain", headamp) }

    static func address(of setting: ReGain.Setting) -> String {
        let base = String(format: "/ch/%02d", setting.channel)
        return switch setting.parameter {
        case .gateThreshold: base + "/gate/thr"
        case .compressorThreshold: base + "/dyn/thr"
        case .mainFader: base + "/mix/fader"
        case .otherMain: base + "/mix/mlevel"
        case .send(let bus): String(format: "%@/mix/%02d/level", base, bus)
        }
    }

    static func scale(of parameter: ReGain.Parameter) -> X32Values {
        switch parameter {
        case .gateThreshold: .gateThreshold
        case .compressorThreshold: .compressorThreshold
        case .mainFader: .fader
        case .otherMain, .send: .level
        }
    }
}

/// What `X32Driver.applyReGain` did: the gain it set and what the X32 holds now, with what undo needs.
public struct X32ReGain: Sendable {
    public var channel: Int
    public var headamp: Int
    public var fromGainDb: Double
    public var toGainDb: Double
    /// Re-Gain's plan, including what limited the step (`limitedBy`).
    public var plan: ReGain.Plan
    /// Each compensated setting as the X32 holds it now: the plan's value on the X32's nearest step.
    public var held: [ReGain.Setting: Double]
    /// Each changed address's raw value before, for `undo`.
    var restore: [String: Float]
}

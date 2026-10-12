import AutoGain
import OSC

/// Preamp gain on an X-Air, and the settings Re-Gain compensates (#153). Addresses and scales as read on Eric's
/// XR18 (firmware 1.26), the same scales as the X32's (`X32Values`) except the aux line in's preamps.
extension XAirDriver: GainControl, ReGainDesk {
    /// The preamp (1-18) behind input channel `channel` (1-16), from its input source: In01-16 are preamps 1-16, the
    /// aux line in (L, R) preamps 17-18, and OFF has none.
    public func headamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? {
        let source = Int(try await queries.int(at: String(format: "/ch/%02d/config/insrc", channel)))
        return (0...17).contains(source) ? source + 1 : nil
    }

    /// The gain of preamp `headamp` (1-18), in dB.
    public func gainDb(ofHeadamp headamp: Int) async throws(MixerLinkProblem) -> Double {
        try await deskGainDb(ofHeadamp: headamp)
    }

    /// What Re-Gain needs to know about input channel `channel` (1-16), read fresh: gate and compressor thresholds,
    /// the fader (main LR) and its 10 sends (buses 1-6, FX 1-4), each pre or post from its own tap: IN, PREEQ,
    /// POSTEQ and PRE are before the fader, POST and GRP after it. The X-Air has no mono or center.
    public func reGainState(ofChannel channel: Int) async throws(MixerLinkProblem) -> ReGain.ChannelState {
        let base = String(format: "/ch/%02d", channel)
        let gate = X32Values.gateThreshold.db(ofOSC: try await queries.float(at: base + "/gate/thr"))
        let compressor = X32Values.compressorThreshold.db(ofOSC: try await queries.float(at: base + "/dyn/thr"))
        let fader = X32Values.fader.db(ofOSC: try await queries.float(at: base + "/mix/fader"))
        var sends: [ReGain.Send] = []
        for bus in 1...Self.sendCount {
            let address = String(format: "%@/mix/%02d", base, bus)
            let preFader = try await queries.int(at: address + "/tap") <= 3
            let level = X32Values.level.db(ofOSC: try await queries.float(at: address + "/level"))
            sends.append(ReGain.Send(bus: bus, levelDb: level, preFader: preFader))
        }
        return ReGain.ChannelState(channel: channel, gateThresholdDb: gate, compressorThresholdDb: compressor,
                                   mainFaderDb: fader, otherMainsDb: [:], sends: sends)
    }

    /// Gates and compressors on other channels keyed from `channel`. On the X-Air a key is a channel (1-16; 17-22 are
    /// buses, 0 is the channel's own signal), not an input as on the X32.
    public func keyedDynamics(from channel: Int) async throws(MixerLinkProblem) -> [ReGain.KeyedDynamics] {
        var keyed: [ReGain.KeyedDynamics] = []
        for other in 1...16 where other != channel {
            let base = String(format: "/ch/%02d", other)
            if Int(try await queries.int(at: base + "/gate/keysrc")) == channel {
                let threshold = X32Values.gateThreshold.db(ofOSC: try await queries.float(at: base + "/gate/thr"))
                keyed.append(ReGain.KeyedDynamics(channel: other, dynamics: .gate, thresholdDb: threshold, keyChannel: channel))
            }
            if Int(try await queries.int(at: base + "/dyn/keysrc")) == channel {
                let threshold = X32Values.compressorThreshold.db(ofOSC: try await queries.float(at: base + "/dyn/thr"))
                keyed.append(ReGain.KeyedDynamics(channel: other, dynamics: .compressor, thresholdDb: threshold, keyChannel: channel))
            }
        }
        return keyed
    }

    /// Moves input channel `channel`'s preamp by `gainChangeDb` with Re-Gain: see `ReGainDesk`.
    public func applyReGain(channel: Int, gainChangeDb: Double, scopes: ReGain.Scopes = .all) async throws(MixerLinkProblem) -> GainStep {
        try await reGain(channel: channel, gainChangeDb: gainChangeDb, scopes: scopes)
    }

    /// Puts back every value `step` changed: see `ReGainDesk`.
    public func undo(_ step: GainStep) async throws(MixerLinkProblem) {
        try await undoReGain(step)
    }

    /// The input channel USB Channel `usbChannel` carries, from the routing read on connect. The aux return has no
    /// preamp of its own, so it isn't one.
    public func channel(forUSBChannel usbChannel: Int) -> Int? {
        let targets = linked.withLock { $0.targets }
        guard targets.indices.contains(usbChannel - 1), case .channel(let channel)? = targets[usbChannel - 1] else { return nil }
        return channel
    }

    /// Buses 1-6 and FX 1-4.
    static let sendCount = 10

    static func gainAddress(_ headamp: Int) -> String { String(format: "/headamp/%02d/gain", headamp) }

    /// Preamps 1-16: -12 to +60 dB. The aux line in (17-18): -12 to +20 dB.
    static func gainScale(_ headamp: Int) -> X32Values {
        headamp >= 17 ? .linear(-12, 20) : .headampGain
    }

    static func address(of setting: ReGain.Setting) -> String {
        let base = String(format: "/ch/%02d", setting.channel)
        return switch setting.parameter {
        case .gateThreshold: base + "/gate/thr"
        case .compressorThreshold: base + "/dyn/thr"
        case .mainFader: base + "/mix/fader"
        case .otherMain: base + "/mix/fader"   // the X-Air has none; never planned
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

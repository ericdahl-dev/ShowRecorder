import AutoGain
import OSC

/// Preamp gain on an X32, and the settings Mix Hold compensates (#392). Values follow `X32Values`.
extension X32Driver {
    /// The preamp (headamp 0–127) behind input channel `channel` (1–32), as the X32 reports it (`/-ha/NN/index`): 0–31
    /// local inputs, 32–79 AES50 A, 80–127 AES50 B. Nil when the channel has none, such as a card or USB source.
    public func headamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? {
        let index = Int(try await queries.int(at: String(format: "/-ha/%02d/index", channel - 1)))
        return (0...127).contains(index) ? index : nil
    }

    /// What Mix Hold needs to know about input channel `channel` (1–32), read fresh: gate and compressor thresholds, the
    /// fader (main LR), the mono/center level (other main 1), and its 16 bus sends. A send's pre or post comes from its
    /// pair's type (set on the odd send): IN/LC, <-EQ, EQ-> and PRE are before the fader, POST and GRP after it.
    public func mixHoldState(ofChannel channel: Int) async throws(MixerLinkProblem) -> MixHold.ChannelState {
        let base = String(format: "/ch/%02d", channel)
        let gate = X32Values.gateThreshold.db(ofOSC: try await queries.float(at: base + "/gate/thr"))
        let compressor = X32Values.compressorThreshold.db(ofOSC: try await queries.float(at: base + "/dyn/thr"))
        let fader = X32Values.fader.db(ofOSC: try await queries.float(at: base + "/mix/fader"))
        let mono = X32Values.level.db(ofOSC: try await queries.float(at: base + "/mix/mlevel"))
        var sends: [MixHold.Send] = []
        var preFader = false
        for bus in 1...16 {
            let address = String(format: "%@/mix/%02d", base, bus)
            if bus % 2 == 1 { preFader = try await queries.int(at: address + "/type") <= 3 }
            let level = X32Values.level.db(ofOSC: try await queries.float(at: address + "/level"))
            sends.append(MixHold.Send(bus: bus, levelDb: level, preFader: preFader))
        }
        return MixHold.ChannelState(channel: channel, gateThresholdDb: gate, compressorThresholdDb: compressor,
                                   mainFaderDb: fader, otherMainsDb: [1: mono], sends: sends)
    }

    /// Gates and compressors on other channels whose key source is `channel`'s input, read fresh. The X32 keys from a
    /// source, not a channel: key 1–64 is the same list as a channel's source (In01…, aux, USB, FX, buses), and 0 is
    /// the channel's own signal. A channel with no source (off) keys nothing.
    public func keyedDynamics(from channel: Int) async throws(MixerLinkProblem) -> [MixHold.KeyedDynamics] {
        let source = Int(try await queries.int(at: String(format: "/ch/%02d/config/source", channel)))
        guard (1...64).contains(source) else { return [] }
        var keyed: [MixHold.KeyedDynamics] = []
        for other in 1...32 where other != channel {
            let base = String(format: "/ch/%02d", other)
            if Int(try await queries.int(at: base + "/gate/keysrc")) == source {
                let threshold = X32Values.gateThreshold.db(ofOSC: try await queries.float(at: base + "/gate/thr"))
                keyed.append(MixHold.KeyedDynamics(channel: other, dynamics: .gate, thresholdDb: threshold, keyChannel: channel))
            }
            if Int(try await queries.int(at: base + "/dyn/keysrc")) == source {
                let threshold = X32Values.compressorThreshold.db(ofOSC: try await queries.float(at: base + "/dyn/thr"))
                keyed.append(MixHold.KeyedDynamics(channel: other, dynamics: .compressor, thresholdDb: threshold, keyChannel: channel))
            }
        }
        return keyed
    }

    /// Every input channel (1–32) on `headamp`, `channel` first: on the X32 several channels can take one headamp,
    /// such as two channels on local input 1 (#473). Read fresh, one query a channel.
    public func channels(onHeadamp headamp: Int, movedWith channel: Int) async throws(MixerLinkProblem) -> [Int] {
        var channels = [channel]
        if let partner = try await linkedPartner(of: channel) { channels.append(partner) }
        for other in 1...Self.channelCount where !channels.contains(other) {
            if Int(try await queries.int(at: String(format: "/-ha/%02d/index", other - 1))) == headamp { channels.append(other) }
        }
        return channels
    }

    /// The gain of preamp `headamp` (0–127), in dB.
    public func gainDb(ofHeadamp headamp: Int) async throws(MixerLinkProblem) -> Double {
        try await deskGainDb(ofHeadamp: headamp)
    }

    /// Moves input channel `channel`'s preamp by `gainChangeDb` with Mix Hold (#393): see `MixHoldDesk`.
    public func applyMixHold(channel: Int, gainChangeDb: Double, scopes: MixHold.Scopes = .all) async throws(MixerLinkProblem) -> GainStep {
        try await mixHold(channel: channel, gainChangeDb: gainChangeDb, scopes: scopes)
    }

    /// Puts back every value `result` changed: see `MixHoldDesk`.
    public func undo(_ result: GainStep) async throws(MixerLinkProblem) {
        try await undoMixHold(result)
    }

    /// Every X32 preamp: -12 to +60 dB.
    static func gainScale(_ headamp: Int) -> X32Values { .headampGain }

    static func gainAddress(_ headamp: Int) -> String { String(format: "/headamp/%03d/gain", headamp) }

    /// Whether a channel link also links the headamps ("HA" in the link setup).
    static let preampLinkAddress = "/config/linkcfg/hadly"

    static func address(of setting: MixHold.Setting) -> String {
        let base = String(format: "/ch/%02d", setting.channel)
        return switch setting.parameter {
        case .gateThreshold: base + "/gate/thr"
        case .compressorThreshold: base + "/dyn/thr"
        case .mainFader: base + "/mix/fader"
        case .otherMain: base + "/mix/mlevel"
        case .send(let bus): String(format: "%@/mix/%02d/level", base, bus)
        }
    }

    static func scale(of parameter: MixHold.Parameter) -> X32Values {
        switch parameter {
        case .gateThreshold: .gateThreshold
        case .compressorThreshold: .compressorThreshold
        case .mainFader: .fader
        case .otherMain, .send: .level
        }
    }
}

/// What a mixer can do for auto-gain (#155): say which input channel a USB Channel carries, move that channel's
/// preamp with Mix Hold, and undo it. The X32 driver does it; the X-Air's comes with #153.
public protocol GainControl: Sendable {
    /// The input channel USB Channel `usbChannel` carries, from the routing read on connect; nil when none.
    func channel(forUSBChannel usbChannel: Int) -> Int?
    /// The preamp a gain move on input channel `channel` lands on, read fresh: two channels that answer the same are
    /// one move (#458), such as two X32 channels on one headamp, or a stereo-linked pair, which the Mixer moves
    /// together. Nil when the channel has no preamp.
    func preamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int?
    func applyMixHold(channel: Int, gainChangeDb: Double, scopes: MixHold.Scopes) async throws(MixerLinkProblem) -> GainStep
    func undo(_ step: GainStep) async throws(MixerLinkProblem)
}

/// One gain move with Mix Hold: the gain set, what the mixer holds now, and what undo needs.
public struct GainStep: Equatable, Sendable {
    public var channel: Int
    public var headamp: Int
    public var fromGainDb: Double
    public var toGainDb: Double
    /// What Mix Hold moved, from and to (the plan's values).
    public var changes: [MixHold.Change]
    /// Each compensated setting as the mixer holds it now: the planned value on the mixer's nearest step.
    public var held: [MixHold.Setting: Double]
    /// Why the gain moved less than asked, if it did (`MixHold.Plan.limitedBy`).
    public var limitedBy: MixHold.Limit?
    /// Each changed address's raw value before, for `undo`.
    public var restore: [String: Float]

    public init(channel: Int, headamp: Int, fromGainDb: Double, toGainDb: Double, changes: [MixHold.Change] = [],
                held: [MixHold.Setting: Double], limitedBy: MixHold.Limit?, restore: [String: Float]) {
        self.channel = channel
        self.headamp = headamp
        self.fromGainDb = fromGainDb
        self.toGainDb = toGainDb
        self.changes = changes
        self.held = held
        self.limitedBy = limitedBy
        self.restore = restore
    }
}

extension X32Driver: GainControl, MixHoldDesk {
    public func channel(forUSBChannel usbChannel: Int) -> Int? {
        linked.withLock { $0.routing?.channel(forUSBChannel: usbChannel) }
    }
}

extension MixHold.Parameter {
    /// A fader or send: a level the channel reaches the mix at, as opposed to a threshold.
    var isLevel: Bool {
        switch self {
        case .mainFader, .otherMain, .send: true
        case .gateThreshold, .compressorThreshold: false
        }
    }
}

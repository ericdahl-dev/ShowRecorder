/// Mix Hold (#393): keeps the mix the same when a preamp's gain changes. What is recorded is the preamp output, so the
/// preamp has to move; everything after it moves the other way, so only the recorded level changes. For a gain change
/// of +g dB:
///
/// - the gate and compressor thresholds rise g dB, and so do those on other channels keyed from this one;
/// - the main LR fader and any other mains (the X32's mono/center) fall g dB;
/// - pre-fader sends fall g dB, counting only sends above `Ranges.offDb` (-90 dB), as Mix Hold does;
/// - post-fader sends and DCAs need nothing, since they follow the fader.
///
/// The gain change is limited so that no compensated setting passes its end stop (Mix Hold's red lines), and the plan
/// says which setting limited it. Pure: the state comes in, read fresh from the Mixer just before each step, and the
/// changes go out for the Mixer driver to write with the gain. Ranges are data from the driver, not per-model code.
public enum MixHold {
    /// What Mix Hold compensates, matching Mix Hold's Sends, Gate, Compressor, LR and Other mains switches.
    public struct Scopes: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let sends = Scopes(rawValue: 1 << 0)
        public static let gate = Scopes(rawValue: 1 << 1)
        public static let compressor = Scopes(rawValue: 1 << 2)
        public static let mainLR = Scopes(rawValue: 1 << 3)
        public static let otherMains = Scopes(rawValue: 1 << 4)
        public static let all: Scopes = [.sends, .gate, .compressor, .mainLR, .otherMains]
    }

    /// A Mixer's parameter ranges in dB, passed in by its driver.
    public struct Ranges: Equatable, Sendable {
        /// The main LR fader and other mains, such as -90...10.
        public var fader: ClosedRange<Double>
        public var send: ClosedRange<Double>
        public var gateThreshold: ClosedRange<Double>
        public var compressorThreshold: ClosedRange<Double>
        /// A fader or send at or below this is off: it is left alone and doesn't limit the range, since lowering the
        /// gain would otherwise open it. The same rule holds for sends and faders.
        public var offDb: Double

        public init(fader: ClosedRange<Double>, send: ClosedRange<Double>, gateThreshold: ClosedRange<Double>,
                    compressorThreshold: ClosedRange<Double>, offDb: Double) {
            self.fader = fader
            self.send = send
            self.gateThreshold = gateThreshold
            self.compressorThreshold = compressorThreshold
            self.offDb = offDb
        }
    }

    /// One setting on a channel that Mix Hold can move.
    public enum Parameter: Hashable, Sendable {
        case gateThreshold
        case compressorThreshold
        case mainFader
        /// Another main by number, such as the X32's mono/center.
        case otherMain(Int)
        /// The send to a bus, by bus number.
        case send(Int)
    }

    /// A parameter on a given channel.
    public struct Setting: Hashable, Sendable {
        public var channel: Int
        public var parameter: Parameter
        public init(channel: Int, parameter: Parameter) {
            self.channel = channel
            self.parameter = parameter
        }
    }

    /// A channel's send to a bus.
    public struct Send: Equatable, Sendable {
        public var bus: Int
        public var levelDb: Double
        public var preFader: Bool
        public init(bus: Int, levelDb: Double, preFader: Bool) {
            self.bus = bus
            self.levelDb = levelDb
            self.preFader = preFader
        }
    }

    /// What a gate or compressor listens to (its sidechain key).
    public enum Key: Equatable, Sendable {
        /// The channel's own signal: its threshold follows this channel's preamp.
        case own
        /// Another channel's signal: its threshold follows that channel's preamp.
        case channel(Int)
        /// An input (the X32 keys from a source, not a channel): its threshold follows the preamp of any channel moving
        /// with this one that takes that input (`ChannelState.source`).
        case source(Int)
        /// Something no preamp feeds directly, such as a bus or an FX return.
        case elsewhere
    }

    /// What Mix Hold needs of a channel, read from the Mixer. Nil, or no entry, is a setting the Mixer doesn't have.
    public struct ChannelState: Equatable, Sendable {
        public var channel: Int
        public var gateThresholdDb: Double?
        public var compressorThresholdDb: Double?
        /// What the gate and the compressor listen to. A threshold moves with this channel's preamp only when it hears
        /// that preamp: its own signal, or a channel moving with it (#497).
        public var gateKey: Key = .own
        public var compressorKey: Key = .own
        /// The input the channel takes, where keys name inputs (the X32); nil where they name channels.
        public var source: Int?
        public var mainFaderDb: Double?
        public var otherMainsDb: [Int: Double]
        public var sends: [Send]

        public init(channel: Int, gateThresholdDb: Double? = nil, compressorThresholdDb: Double? = nil,
                    mainFaderDb: Double? = nil, otherMainsDb: [Int: Double] = [:], sends: [Send] = []) {
            self.channel = channel
            self.gateThresholdDb = gateThresholdDb
            self.compressorThresholdDb = compressorThresholdDb
            self.mainFaderDb = mainFaderDb
            self.otherMainsDb = otherMainsDb
            self.sends = sends
        }
    }

    /// One compensated setting, from its value now to its new one.
    public struct Change: Hashable, Sendable {
        public var setting: Setting
        public var fromDb: Double
        public var toDb: Double
        public init(setting: Setting, fromDb: Double, toDb: Double) {
            self.setting = setting
            self.fromDb = fromDb
            self.toDb = toDb
        }
    }

    /// The compensated setting that would hit its end stop first, and that end.
    public struct Limit: Hashable, Sendable {
        public var setting: Setting
        public var endDb: Double
        public init(setting: Setting, endDb: Double) {
            self.setting = setting
            self.endDb = endDb
        }
    }

    /// One gain step and its compensation. Asking for more than the compensable range gives the limited step and
    /// the reason, never a change that would alter the mix.
    public struct Plan: Equatable, Sendable {
        /// The gain change asked for.
        public var requestedDb: Double
        /// The gain change to make: the request, limited to the compensable range.
        public var gainChangeDb: Double
        public var changes: [Change]
        /// Why `gainChangeDb` is less than requested; nil when it isn't.
        public var limitedBy: Limit?

        /// Each compensated setting's new value, to write with the gain.
        public var values: [Setting: Double] {
            Dictionary(changes.map { ($0.setting, $0.toDb) }, uniquingKeysWith: { _, last in last })
        }
    }

    /// The compensation for moving `headamp` by `gainChangeDb`, limited to the compensable range.
    /// - Parameters:
    ///   - channels: every channel the headamp moves, read fresh.
    ///   - keyed: gates and compressors whose sidechain key is another channel, read fresh. Those keyed from a moved
    ///     channel, on a channel that isn't moved, have their threshold moved +g like the moved channels' own.
    public static func plan(
        headamp: Int,
        gainChangeDb: Double,
        channels: [ChannelState],
        ranges: Ranges,
        scopes: Scopes = .all,
        keyed: [KeyedDynamics] = [],
        live: Set<Setting> = []
    ) -> Plan {
        let items = compensated(channels, keyed: keyed, ranges: ranges, scopes: scopes, live: live)
        let range = compensableRange(items)
        var g = gainChangeDb
        var limit: Limit?
        if g > range.highestDb {
            g = range.highestDb
            limit = range.upperLimit
        } else if g < range.lowestDb {
            g = range.lowestDb
            limit = range.lowerLimit
        }
        let changes = items.map { Change(setting: $0.setting, fromDb: $0.valueDb, toDb: $0.valueDb + $0.direction * g) }
        return Plan(requestedDb: gainChangeDb, gainChangeDb: g, changes: changes, limitedBy: limit)
    }

    /// How far the gain can move each way before a compensated setting reaches its end stop: Mix Hold's red lines.
    public struct CompensableRange: Equatable, Sendable {
        /// The largest cut, in dB (zero or below); -infinity when nothing limits it.
        public var lowestDb: Double
        /// The largest boost, in dB (zero or above); +infinity when nothing limits it.
        public var highestDb: Double
        /// The setting that ends the range going down, and the setting that ends it going up.
        public var lowerLimit: Limit?
        public var upperLimit: Limit?
    }

    public static func compensableRange(channels: [ChannelState], keyed: [KeyedDynamics] = [], ranges: Ranges,
                                        scopes: Scopes = .all) -> CompensableRange {
        compensableRange(compensated(channels, keyed: keyed, ranges: ranges, scopes: scopes))
    }

    static func compensableRange(_ items: [Item]) -> CompensableRange {
        var result = CompensableRange(lowestDb: -.infinity, highestDb: .infinity)
        for item in items {
            // A threshold rises with the gain, so its top ends a boost; a fader or send falls, so its bottom does.
            let boostEnd = item.direction > 0 ? item.range.upperBound : item.range.lowerBound
            let cutEnd = item.direction > 0 ? item.range.lowerBound : item.range.upperBound
            let boost = max((boostEnd - item.valueDb) * item.direction, 0)
            let cut = min((cutEnd - item.valueDb) * item.direction, 0)
            if boost < result.highestDb {
                result.highestDb = boost
                result.upperLimit = Limit(setting: item.setting, endDb: boostEnd)
            }
            if cut > result.lowestDb {
                result.lowestDb = cut
                result.lowerLimit = Limit(setting: item.setting, endDb: cutEnd)
            }
        }
        return result
    }

    /// A gate or compressor whose sidechain key is another channel, with its threshold now. When the key channel's
    /// gain moves, so does what the threshold sees, so Mix Hold moves the threshold too (Eric, 2026-10-12).
    public struct KeyedDynamics: Hashable, Sendable {
        public enum Dynamics: Hashable, Sendable {
            case gate
            case compressor
        }

        public var channel: Int
        public var dynamics: Dynamics
        public var thresholdDb: Double
        public var keyChannel: Int
        public init(channel: Int, dynamics: Dynamics, thresholdDb: Double, keyChannel: Int) {
            self.channel = channel
            self.dynamics = dynamics
            self.thresholdDb = thresholdDb
            self.keyChannel = keyChannel
        }
    }

    /// A setting Mix Hold moves: +1 with the gain (thresholds), -1 against it (faders and sends).
    struct Item {
        var setting: Setting
        var valueDb: Double
        var direction: Double
        var range: ClosedRange<Double>
    }

    static func compensated(_ channels: [ChannelState], keyed: [KeyedDynamics] = [], ranges: Ranges, scopes: Scopes,
                            live: Set<Setting> = []) -> [Item] {
        var items: [Item] = []
        let moved = Set(channels.map(\.channel))
        for state in channels {
            func add(_ parameter: Parameter, _ value: Double?, _ direction: Double, _ range: ClosedRange<Double>) {
                guard let value, scopes.contains(scope(of: parameter)) else { return }
                if direction < 0, value <= ranges.offDb { return }
                let setting = Setting(channel: state.channel, parameter: parameter)
                if !live.contains(setting), idle(parameter, value, ranges: ranges) { return }
                items.append(Item(setting: setting, valueDb: value, direction: direction, range: range))
            }
            // A gate or compressor keyed from elsewhere doesn't hear this preamp: moving its threshold would change how
            // hard it works, and so the mix. One keyed from another channel moves with that channel (`keyed`).
            func hears(_ key: Key) -> Bool {
                switch key {
                case .own: true
                case .channel(let other): moved.contains(other)
                case .source(let input): channels.contains { $0.source == input }
                case .elsewhere: false
                }
            }
            if hears(state.gateKey) { add(.gateThreshold, state.gateThresholdDb, 1, ranges.gateThreshold) }
            if hears(state.compressorKey) { add(.compressorThreshold, state.compressorThresholdDb, 1, ranges.compressorThreshold) }
            add(.mainFader, state.mainFaderDb, -1, ranges.fader)
            for (main, level) in state.otherMainsDb.sorted(by: { $0.key < $1.key }) {
                add(.otherMain(main), level, -1, ranges.fader)
            }
            for send in state.sends where send.preFader {
                add(.send(send.bus), send.levelDb, -1, ranges.send)
            }
        }
        for dynamics in keyed where moved.contains(dynamics.keyChannel) && !moved.contains(dynamics.channel) {
            let parameter: Parameter = dynamics.dynamics == .gate ? .gateThreshold : .compressorThreshold
            guard scopes.contains(scope(of: parameter)) else { continue }
            // Keyed from two moved channels (they share an input): one setting, moved once.
            let setting = Setting(channel: dynamics.channel, parameter: parameter)
            guard !items.contains(where: { $0.setting == setting }) else { continue }
            if !live.contains(setting), idle(parameter, dynamics.thresholdDb, ranges: ranges) { continue }
            let range = dynamics.dynamics == .gate ? ranges.gateThreshold : ranges.compressorThreshold
            items.append(Item(setting: Setting(channel: dynamics.channel, parameter: parameter), valueDb: dynamics.thresholdDb,
                              direction: 1, range: range))
        }
        return items
    }

    /// A threshold already at an edge where it does nothing, which Mix Hold leaves as it is, with no end stop (#685): a
    /// compressor at its top (never acts) or a gate at its bottom (always open). Not one auto-gain moved there itself
    /// (`live`): that keeps its end stop, or the next step would make it work harder and change the mix.
    static func idle(_ parameter: Parameter, _ valueDb: Double, ranges: Ranges) -> Bool {
        switch parameter {
        case .compressorThreshold: valueDb >= ranges.compressorThreshold.upperBound
        case .gateThreshold: valueDb <= ranges.gateThreshold.lowerBound
        case .mainFader, .otherMain, .send: false
        }
    }

    static func scope(of parameter: Parameter) -> Scopes {
        switch parameter {
        case .gateThreshold: .gate
        case .compressorThreshold: .compressor
        case .mainFader: .mainLR
        case .otherMain: .otherMains
        case .send: .sends
        }
    }
}

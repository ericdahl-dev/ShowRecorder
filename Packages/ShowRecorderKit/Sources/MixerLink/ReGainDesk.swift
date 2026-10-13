import AutoGain
import OSC

/// A Behringer desk Re-Gain can drive (#392, #153): the X32 and the X-Air differ in addresses, scales and which preamp
/// a channel uses; how a gain move is planned, written, ramped and undone is the same, and lives here.
protocol ReGainDesk: GainControl {
    var queries: MixerQueries { get }
    var client: OSCUDPClient { get }
    func identify() async throws(MixerLinkProblem) -> MixerIdentity
    /// The preamp behind input channel `channel`, or nil when it has none.
    func headamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int?
    func reGainState(ofChannel channel: Int) async throws(MixerLinkProblem) -> ReGain.ChannelState
    func keyedDynamics(from channel: Int) async throws(MixerLinkProblem) -> [ReGain.KeyedDynamics]
    static func gainAddress(_ headamp: Int) -> String
    static func gainScale(_ headamp: Int) -> X32Values
    static func address(of setting: ReGain.Setting) -> String
    static func scale(of parameter: ReGain.Parameter) -> X32Values
}

/// One compensated setting moving from one value to another.
struct ReGainMove {
    var setting: ReGain.Setting
    var fromDb: Double
    var toDb: Double
}

extension ReGainDesk {
    /// The most the gain moves in one ramp step, in dB.
    static var rampStepDb: Double { 1.0 }

    func deskGainDb(ofHeadamp headamp: Int) async throws(MixerLinkProblem) -> Double {
        Self.gainScale(headamp).db(ofOSC: try await queries.float(at: Self.gainAddress(headamp)))
    }

    /// Moves input channel `channel`'s preamp by `gainChangeDb` and compensates everything after it with Re-Gain
    /// (#393), so the mix stays the same and only the recorded level moves. Everything is read fresh first.
    ///
    /// The gain stops at the preamp's range and at what Re-Gain can compensate (`limitedBy`), and every value is
    /// written on one of the desk's own steps: `held` is what it holds afterwards, which can differ from the plan by
    /// up to half a step. Never call it during a Take (#155 doesn't offer it then).
    func reGain(channel: Int, gainChangeDb: Double, scopes: ReGain.Scopes) async throws(MixerLinkProblem) -> GainStep {
        guard let headamp = try await headamp(ofChannel: channel) else { throw .noPreamp(channel: channel) }
        let gainScale = Self.gainScale(headamp)
        let from = try await deskGainDb(ofHeadamp: headamp)
        let reachable = gainScale.snap(from + gainChangeDb) - from
        let state = try await reGainState(ofChannel: channel)
        let keyed = try await keyedDynamics(from: channel)
        let ranges = Self.reGainRanges
        let plan = ReGain.plan(headamp: headamp, gainChangeDb: reachable, channels: [state], ranges: ranges, scopes: scopes, keyed: keyed)
        let to = gainScale.snap(from + plan.gainChangeDb)

        // The raw value of every address about to change, so undo restores it exactly.
        var addresses = [Self.gainAddress(headamp)]
        addresses += plan.values.keys.map { Self.address(of: $0) }
        var restore: [String: Float] = [:]
        for address in addresses { restore[address] = try await queries.float(at: address) }

        var held: [ReGain.Setting: Double] = [:]
        for (setting, db) in plan.values { held[setting] = Self.scale(of: setting.parameter).snap(db) }
        try await ramp(headamp: headamp, gainFrom: from, gainTo: to,
                       moves: plan.changes.map { ReGainMove(setting: $0.setting, fromDb: $0.fromDb, toDb: $0.toDb) })
        return GainStep(channel: channel, headamp: headamp, fromGainDb: from, toGainDb: to, changes: plan.changes, held: held,
                        limitedBy: plan.limitedBy, restore: restore)
    }

    /// Puts back every value `result` changed: ramps back the way it came, then writes the exact values read before.
    func undoReGain(_ result: GainStep) async throws(MixerLinkProblem) {
        let gainAddress = Self.gainAddress(result.headamp)
        try await ramp(headamp: result.headamp, gainFrom: result.toGainDb, gainTo: result.fromGainDb,
                       moves: result.changes.map { ReGainMove(setting: $0.setting, fromDb: result.held[$0.setting] ?? $0.toDb, toDb: $0.fromDb) })
        // The exact raw values, in the same safe order: when the gain went back down, it goes first.
        let others = result.restore.filter { $0.key != gainAddress }
        let lowering = result.toGainDb > result.fromGainDb
        if lowering, let gain = result.restore[gainAddress] { await client.send(OSCMessage(gainAddress, [.float(gain)])) }
        for (address, value) in others { await client.send(OSCMessage(address, [.float(value)])) }
        if !lowering, let gain = result.restore[gainAddress] { await client.send(OSCMessage(gainAddress, [.float(gain)])) }
        _ = try await identify()   // the desk answers, so the writes reached it
    }

    /// Moves the gain and its compensations together in steps of at most `rampStepDb`, so the mix changes smoothly
    /// and never gets louder, even for a moment. Within a step, raising the gain turns everything else first and the
    /// gain last; lowering it does the gain first. A query between the two halves makes the desk apply the first half
    /// before the second arrives. In-between values round down (a level never rounds up); the last step lands exactly
    /// on the plan's values.
    private func ramp(headamp: Int, gainFrom: Double, gainTo: Double, moves: [ReGainMove]) async throws(MixerLinkProblem) {
        let gainAddress = Self.gainAddress(headamp)
        let gainScale = Self.gainScale(headamp)
        let count = max(1, Int((abs(gainTo - gainFrom) / Self.rampStepDb).rounded(.up)))
        let raising = gainTo > gainFrom
        for index in 1...count {
            let fraction = Double(index) / Double(count)
            let last = index == count
            let gainDb = gainFrom + (gainTo - gainFrom) * fraction
            let gain = last ? gainScale.oscFloat(gainDb) : gainScale.oscFloatBelow(gainDb)
            let others = moves.map { move -> OSCMessage in
                let db = move.fromDb + (move.toDb - move.fromDb) * fraction
                let scale = Self.scale(of: move.setting.parameter)
                let level = move.setting.parameter.isLevel
                return OSCMessage(Self.address(of: move.setting), [.float(last || !level ? scale.oscFloat(db) : scale.oscFloatBelow(db))])
            }
            if raising {
                for message in others { await client.send(message) }
                _ = try await identify()
                await client.send(OSCMessage(gainAddress, [.float(gain)]))
            } else {
                await client.send(OSCMessage(gainAddress, [.float(gain)]))
                _ = try await identify()
                for message in others { await client.send(message) }
            }
        }
        _ = try await identify()   // the desk answers, so every write reached it
    }
}

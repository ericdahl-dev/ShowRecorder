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
    /// Where the Mixer says whether a stereo link also links the preamps (`/config/linkcfg/…`).
    static var preampLinkAddress: String { get }
    /// Every input channel a move of `headamp` changes, `channel` (the one asked for) first. Most desks give each
    /// channel its own preamp; on the X32 several channels can take one headamp (#473).
    func channels(onHeadamp headamp: Int, movedWith channel: Int) async throws(MixerLinkProblem) -> [Int]
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
    public func channels(onHeadamp headamp: Int, movedWith channel: Int) async throws(MixerLinkProblem) -> [Int] {
        [channel]
    }

    /// The most the gain moves in one ramp step, in dB.
    static var rampStepDb: Double { 1.0 }

    /// The preamp a move on input channel `channel` lands on (#458): its own, or, when it is the second of a
    /// stereo-linked pair (`/config/chlink/1-2` on the X-Air and the X32) whose preamps are linked too
    /// (`preampLinkAddress`), the first channel's, since the Mixer then moves both together. A link of the channel
    /// strips alone leaves each its own preamp. Two X32 channels on one headamp answer the same headamp.
    public func preamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? {
        guard channel % 2 == 0,
              try await queries.int(at: String(format: "/config/chlink/%d-%d", channel - 1, channel)) != 0,
              try await queries.int(at: Self.preampLinkAddress) != 0
        else { return try await headamp(ofChannel: channel) }
        return try await headamp(ofChannel: channel - 1)
    }

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
        // Every channel on this preamp moves with it, so Re-Gain compensates each of them (#473).
        var states: [ReGain.ChannelState] = []
        var keyed: Set<ReGain.KeyedDynamics> = []
        for moved in try await channels(onHeadamp: headamp, movedWith: channel) {
            states.append(try await reGainState(ofChannel: moved))
            keyed.formUnion(try await keyedDynamics(from: moved))
        }
        let ranges = Self.reGainRanges
        let plan = ReGain.plan(headamp: headamp, gainChangeDb: reachable, channels: states, ranges: ranges, scopes: scopes, keyed: Array(keyed))
        let to = gainScale.snap(from + plan.gainChangeDb)

        // The raw value of every address about to change, so undo restores it exactly.
        var addresses = [Self.gainAddress(headamp)]
        addresses += plan.values.keys.map { Self.address(of: $0) }
        var restore: [String: Float] = [:]
        for address in addresses { restore[address] = try await queries.float(at: address) }

        var held: [ReGain.Setting: Double] = [:]
        for (setting, db) in plan.values { held[setting] = Self.scale(of: setting.parameter).snap(db) }
        var sent: [String: Float] = [:]
        do throws(MixerLinkProblem) {
            try await ramp(headamp: headamp, gainFrom: from, gainTo: to,
                           moves: plan.changes.map { ReGainMove(setting: $0.setting, fromDb: $0.fromDb, toDb: $0.toDb) }, sent: &sent)
        } catch {
            guard !sent.isEmpty else { throw error }
            // Partway: report what was written, so it is logged and Undo can take it back (#450).
            let gainAddress = Self.gainAddress(headamp)
            let partialTo = sent[gainAddress].map { gainScale.db(ofOSC: $0) } ?? from
            var partialHeld: [ReGain.Setting: Double] = [:]
            var partialChanges: [ReGain.Change] = []
            for change in plan.changes {
                guard let value = sent[Self.address(of: change.setting)] else { continue }
                let db = Self.scale(of: change.setting.parameter).db(ofOSC: value)
                partialHeld[change.setting] = db
                partialChanges.append(ReGain.Change(setting: change.setting, fromDb: change.fromDb, toDb: db))
            }
            throw .gainMoveInterrupted(GainStep(channel: channel, headamp: headamp, fromGainDb: from, toGainDb: partialTo,
                                                changes: partialChanges, held: partialHeld, limitedBy: plan.limitedBy, restore: restore))
        }
        return GainStep(channel: channel, headamp: headamp, fromGainDb: from, toGainDb: to, changes: plan.changes, held: held,
                        limitedBy: plan.limitedBy, restore: restore)
    }

    /// Puts back every value `result` changed: ramps back the way it came, then writes the exact values read before.
    func undoReGain(_ result: GainStep) async throws(MixerLinkProblem) {
        let gainAddress = Self.gainAddress(result.headamp)
        var sent: [String: Float] = [:]
        try await ramp(headamp: result.headamp, gainFrom: result.toGainDb, gainTo: result.fromGainDb,
                       moves: result.changes.map { ReGainMove(setting: $0.setting, fromDb: result.held[$0.setting] ?? $0.toDb, toDb: $0.fromDb) },
                       sent: &sent)
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
    /// `sent` gets every value written, by address, as it goes: if the desk stops answering partway, it is what the
    /// desk was last told.
    private func ramp(headamp: Int, gainFrom: Double, gainTo: Double, moves: [ReGainMove],
                      sent: inout [String: Float]) async throws(MixerLinkProblem) {
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
            let gainMessage = OSCMessage(gainAddress, [.float(gain)])
            if raising {
                for message in others { await send(message, recordingIn: &sent) }
                _ = try await identify()
                await send(gainMessage, recordingIn: &sent)
            } else {
                await send(gainMessage, recordingIn: &sent)
                _ = try await identify()
                for message in others { await send(message, recordingIn: &sent) }
            }
        }
        _ = try await identify()   // the desk answers, so every write reached it
    }

    private func send(_ message: OSCMessage, recordingIn sent: inout [String: Float]) async {
        await client.send(message)
        if case .float(let value)? = message.arguments.first { sent[message.address] = value }
    }
}

import AutoGain
import MixerLink
import TakeFile

/// Auto-gain on the record screen (#155): brings USB Channels to the target level by moving their preamps on the
/// Mixer with Re-Gain, so the mix stays the same. It measures with our own meters, the level actually recorded.
/// Never during a Take: the screen doesn't offer it then.
@MainActor
public final class AutoGainSession {
    /// What happened to one USB Channel.
    public enum Result: Equatable, Sendable {
        /// Its preamp moved from one gain to another and it ended at `levelDbfs`, in the target band.
        case set(usbChannel: Int, channel: Int, fromGainDb: Double, toGainDb: Double, levelDbfs: Double)
        /// Left alone, and why.
        case skipped(usbChannel: Int, reason: Skip)
        /// The rule couldn't bring it to target; whatever gain it set stays, for Undo. `limitedBy` is the setting that
        /// stopped Re-Gain going further, when that's why (a threshold at its top, say), rather than the preamp's range.
        case failed(usbChannel: Int, channel: Int, failure: AutoGainRule.Failure, limitedBy: ReGain.Limit? = nil)
        /// Its level didn't follow the gain, so the gain moved somewhere else (the USB routing isn't what was read).
        /// It stopped and put that gain back.
        case stopped(usbChannel: Int, channel: Int)
        /// The Mixer didn't do what was asked (it stopped answering, say); whatever gain it set stays, for Undo.
        case error(usbChannel: Int, channel: Int, problem: MixerLinkProblem)
        /// A Take started, so the run stopped at once: no gain moves during a Take. Whatever gain it set stays, for Undo.
        case haltedForTake(usbChannel: Int, channel: Int)
    }

    public enum Skip: Equatable, Sendable {
        /// Nothing on it to measure.
        case noSignal
        /// No Mixer input channel is routed to it (an output, say, or a digital source).
        case noChannel
        /// It carries the same Mixer channel as an earlier USB Channel, whose preamp already moved.
        case sameChannel(asUSBChannel: Int)
        /// Its Mixer channel shares a preamp with an earlier USB Channel's (a shared headamp, a stereo link), and that
        /// preamp already moved (#458).
        case samePreamp(asUSBChannel: Int)
    }

    private let control: any GainControl
    private let rule: AutoGainRule
    private let measure: (Int) async -> Double
    private let settle: () async -> Void
    /// Told about every gain change made and undone (#450): the Recorder logs it in the Take or the Show.
    private let log: (TakeMetadata.GainChange) -> Void
    /// A level that misses where a gain move should have put it by more than this means the move went elsewhere.
    static let followToleranceDb = 6.0

    private struct LevelDidNotFollow: Error {}
    private struct StoppedForTake: Error {}
    /// Set by `stop()`: no more gain moves in this run.
    private var stopRequested = false

    /// Stops a run under way at once, before its next gain move (a Take started). The channel it was on says so;
    /// channels after it are left alone. Every move made stays for Undo.
    public func stop() {
        stopRequested = true
    }
    /// Every gain step taken, by USB Channel, for Undo.
    public private(set) var steps: [Int: [GainStep]] = [:]

    /// - Parameters:
    ///   - measure: a USB Channel's Average level now, in dBFS, from the meters.
    ///   - settle: waits for the meters to follow a gain move before measuring again.
    public init(control: any GainControl, rule: AutoGainRule = AutoGainRule(), measure: @escaping (Int) async -> Double,
                settle: @escaping () async -> Void = {}, log: @escaping (TakeMetadata.GainChange) -> Void = { _ in }) {
        self.control = control
        self.log = log
        self.rule = rule
        self.measure = measure
        self.settle = settle
    }

    /// Runs auto-gain on each of `usbChannels` and says what happened to each.
    public func run(usbChannels: [Int]) async -> [Result] {
        stopRequested = false
        var results: [Result] = []
        var done: [Int: Int] = [:]   // Mixer channel -> the USB Channel that moved it
        var donePreamps: [Int: Int] = [:]   // preamp -> the USB Channel that moved it
        for usbChannel in usbChannels {
            if stopRequested { break }
            guard let channel = control.channel(forUSBChannel: usbChannel) else {
                results.append(.skipped(usbChannel: usbChannel, reason: .noChannel))
                continue
            }
            if let earlier = done[channel] {
                results.append(.skipped(usbChannel: usbChannel, reason: .sameChannel(asUSBChannel: earlier)))
                continue
            }
            done[channel] = usbChannel
            let preamp: Int?
            do throws(MixerLinkProblem) {
                preamp = try await control.preamp(ofChannel: channel)
            } catch {
                results.append(.error(usbChannel: usbChannel, channel: channel, problem: error))
                continue
            }
            if let preamp {
                if let earlier = donePreamps[preamp] {
                    results.append(.skipped(usbChannel: usbChannel, reason: .samePreamp(asUSBChannel: earlier)))
                    continue
                }
                donePreamps[preamp] = usbChannel
            }
            var taken: [GainStep] = []
            var expected: Double?   // where the last move should have put the level
            var lastLevel = 0.0
            var limit: ReGain.Limit?   // what limited the latest step, if anything did
            let outcome: AutoGainRule.Outcome
            do {
                outcome = try await rule.run(
                    measure: {
                        let level = await measure(usbChannel)
                        // Our meters measure what's recorded: if the level didn't follow the gain, the wrong preamp moved.
                        if let expected, abs(level - expected) > Self.followToleranceDb { throw LevelDidNotFollow() }
                        lastLevel = level
                        return level
                    },
                    adjust: { db in
                        if stopRequested { throw StoppedForTake() }
                        let step: GainStep
                        do throws(MixerLinkProblem) {
                            step = try await control.applyReGain(channel: channel, gainChangeDb: db, scopes: .all)
                        } catch {
                            // Stopped partway: what was written is logged and kept for Undo (#450), then the run ends.
                            if case .gainMoveInterrupted(let partial) = error {
                                taken.append(partial)
                                log(Self.change(partial, usbChannel: usbChannel, reason: .autoGain))
                            }
                            throw error
                        }
                        let applied = step.toGainDb - step.fromGainDb
                        limit = step.limitedBy
                        // A step that moved nothing changed nothing: there's nothing to log or undo. A setting can move
                        // while the gain snaps back to where it was, so that counts as a move.
                        if applied != 0 || step.changes.contains(where: { step.held[$0.setting] ?? $0.toDb != $0.fromDb }) {
                            taken.append(step)
                            log(Self.change(step, usbChannel: usbChannel, reason: .autoGain))
                        }
                        expected = lastLevel + applied
                        return applied
                    },
                    settle: { await settle() }
                )
            } catch is StoppedForTake {
                steps[usbChannel, default: []] += taken
                results.append(.haltedForTake(usbChannel: usbChannel, channel: channel))
                break
            } catch is LevelDidNotFollow {
                // Newest first; a step the Mixer wouldn't take back stays for Undo, with every older one, and the
                // result is the Mixer's problem rather than "stopped", which says the gain was put back.
                var undoProblem: MixerLinkProblem?
                while undoProblem == nil, let step = taken.last {
                    do throws(MixerLinkProblem) {
                        try await control.undo(step)
                        taken.removeLast()
                        log(Self.change(step, usbChannel: usbChannel, reason: .undo, undoing: true))
                    } catch {
                        undoProblem = error
                    }
                }
                steps[usbChannel, default: []] += taken
                if let undoProblem {
                    results.append(.error(usbChannel: usbChannel, channel: channel, problem: undoProblem))
                } else {
                    results.append(.stopped(usbChannel: usbChannel, channel: channel))
                }
                continue
            } catch let problem as MixerLinkProblem {
                steps[usbChannel, default: []] += taken
                results.append(.error(usbChannel: usbChannel, channel: channel, problem: problem))
                continue
            } catch {
                steps[usbChannel, default: []] += taken
                results.append(.error(usbChannel: usbChannel, channel: channel, problem: .other(String(describing: error))))
                continue
            }
            // Added to any earlier run's steps on this USB Channel, so Undo goes all the way back.
            steps[usbChannel, default: []] += taken
            switch outcome {
            case .onTarget(let level, _, _):
                if let first = taken.first, let last = taken.last {
                    results.append(.set(usbChannel: usbChannel, channel: channel, fromGainDb: first.fromGainDb, toGainDb: last.toGainDb, levelDbfs: level))
                }
            case .failed(.noSignal, _):
                results.append(.skipped(usbChannel: usbChannel, reason: .noSignal))
            case .failed(let failure, _):
                let limitedBy: ReGain.Limit? = if case .rangeReached = failure { limit } else { nil }
                results.append(.failed(usbChannel: usbChannel, channel: channel, failure: failure, limitedBy: limitedBy))
            }
        }
        return results
    }

    /// Puts back every gain step taken on `usbChannel`, newest first.
    /// USB Channels with an Undo under way.
    private var undoing: Set<Int> = []

    /// Each step is dropped as soon as it is undone, so when the Mixer stops answering partway the rest stay for
    /// another Undo, and none is undone twice. An Undo asked for while one is under way on the same USB Channel does
    /// nothing: the first one takes back every step.
    public func undo(usbChannel: Int) async throws(MixerLinkProblem) {
        guard undoing.insert(usbChannel).inserted else { return }
        defer { undoing.remove(usbChannel) }
        while let step = steps[usbChannel]?.last {
            try await control.undo(step)
            if steps[usbChannel]?.last == step { steps[usbChannel]?.removeLast() }
            log(Self.change(step, usbChannel: usbChannel, reason: .undo, undoing: true))
        }
    }

    /// Puts back every gain step of the run.
    public func undoAll() async throws(MixerLinkProblem) {
        for usbChannel in steps.keys.sorted().reversed() { try await undo(usbChannel: usbChannel) }
    }

    /// A gain step as the log records it: the gain and every compensated setting from and to (reversed for an undo).
    static func change(_ step: GainStep, usbChannel: Int, reason: TakeMetadata.GainChange.Reason, undoing: Bool = false) -> TakeMetadata.GainChange {
        let compensations = step.changes.map { change in
            let held = step.held[change.setting] ?? change.toDb
            return TakeMetadata.GainChange.Compensation(
                channel: change.setting.channel, setting: change.setting.parameter.logName,
                fromDb: undoing ? held : change.fromDb, toDb: undoing ? change.fromDb : held)
        }
        return TakeMetadata.GainChange(
            usbChannel: usbChannel, channel: step.channel, headamp: step.headamp,
            fromGainDb: undoing ? step.toGainDb : step.fromGainDb, toGainDb: undoing ? step.fromGainDb : step.toGainDb,
            reason: reason, compensations: compensations)
    }
}

extension ReGain.Limit {
    /// The setting that stopped Re-Gain and its end stop, as the auto-gain sheet says it: "Channel 1's gate threshold
    /// is at its end stop (0 dB)".
    public var explanation: String {
        let db = endDb > 0 ? String(format: "+%g", endDb) : String(format: "%g", endDb)
        return "Channel \(setting.channel)'s \(setting.parameter.logName) is at its end stop (\(db) dB)"
    }
}

extension ReGain.Parameter {
    /// "gate threshold", "fader", "send 3", as the gain log names it.
    var logName: String {
        switch self {
        case .gateThreshold: "gate threshold"
        case .compressorThreshold: "compressor threshold"
        case .mainFader: "fader"
        case .otherMain(let main): main == 1 ? "mono" : "main \(main)"
        case .send(let bus): "send \(bus)"
        }
    }
}

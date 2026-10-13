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
        /// The rule couldn't bring it to target; whatever gain it set stays, for Undo.
        case failed(usbChannel: Int, channel: Int, failure: AutoGainRule.Failure)
        /// Its level didn't follow the gain, so the gain moved somewhere else (the USB routing isn't what was read).
        /// It stopped and put that gain back.
        case stopped(usbChannel: Int, channel: Int)
        /// The Mixer didn't do what was asked (it stopped answering, say); whatever gain it set stays, for Undo.
        case error(usbChannel: Int, channel: Int, problem: MixerLinkProblem)
    }

    public enum Skip: Equatable, Sendable {
        /// Nothing on it to measure.
        case noSignal
        /// No Mixer input channel is routed to it (an output, say, or a digital source).
        case noChannel
        /// It carries the same Mixer channel as an earlier USB Channel, whose preamp already moved.
        case sameChannel(asUSBChannel: Int)
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
        var results: [Result] = []
        var done: [Int: Int] = [:]   // Mixer channel -> the USB Channel that moved it
        for usbChannel in usbChannels {
            guard let channel = control.channel(forUSBChannel: usbChannel) else {
                results.append(.skipped(usbChannel: usbChannel, reason: .noChannel))
                continue
            }
            if let earlier = done[channel] {
                results.append(.skipped(usbChannel: usbChannel, reason: .sameChannel(asUSBChannel: earlier)))
                continue
            }
            done[channel] = usbChannel
            var taken: [GainStep] = []
            var expected: Double?   // where the last move should have put the level
            var lastLevel = 0.0
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
                        let step = try await control.applyReGain(channel: channel, gainChangeDb: db, scopes: .all)
                        taken.append(step)
                        log(Self.change(step, usbChannel: usbChannel, reason: .autoGain))
                        let applied = step.toGainDb - step.fromGainDb
                        expected = lastLevel + applied
                        return applied
                    },
                    settle: { await settle() }
                )
            } catch is LevelDidNotFollow {
                for step in taken.reversed() where (try? await control.undo(step)) != nil {
                    log(Self.change(step, usbChannel: usbChannel, reason: .undo, undoing: true))
                }
                steps[usbChannel] = []
                results.append(.stopped(usbChannel: usbChannel, channel: channel))
                continue
            } catch let problem as MixerLinkProblem {
                steps[usbChannel] = taken
                results.append(.error(usbChannel: usbChannel, channel: channel, problem: problem))
                continue
            } catch {
                steps[usbChannel] = taken
                results.append(.error(usbChannel: usbChannel, channel: channel, problem: .other(String(describing: error))))
                continue
            }
            steps[usbChannel] = taken
            switch outcome {
            case .onTarget(let level, _, _):
                if let first = taken.first, let last = taken.last {
                    results.append(.set(usbChannel: usbChannel, channel: channel, fromGainDb: first.fromGainDb, toGainDb: last.toGainDb, levelDbfs: level))
                }
            case .failed(.noSignal, _):
                results.append(.skipped(usbChannel: usbChannel, reason: .noSignal))
            case .failed(let failure, _):
                results.append(.failed(usbChannel: usbChannel, channel: channel, failure: failure))
            }
        }
        return results
    }

    /// Puts back every gain step taken on `usbChannel`, newest first.
    public func undo(usbChannel: Int) async throws(MixerLinkProblem) {
        for step in (steps[usbChannel] ?? []).reversed() {
            try await control.undo(step)
            log(Self.change(step, usbChannel: usbChannel, reason: .undo, undoing: true))
        }
        steps[usbChannel] = []
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

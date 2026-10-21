import AutoGain
import MixerLink
import TakeFile

/// Auto-gain on the record screen (#155): brings USB Channels to the target level by moving their preamps on the
/// Mixer with Mix Hold, so the mix stays the same. It measures with our own meters, the level actually recorded.
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
        /// stopped Mix Hold going further, when that's why (a threshold at its top, say), rather than the preamp's range.
        case failed(usbChannel: Int, channel: Int, failure: AutoGainRule.Failure, limitedBy: MixHold.Limit? = nil)
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
        /// Its level was already in the target band: nothing moved.
        case alreadyOnTarget(levelDbfs: Double)
        /// No Mixer input channel is routed to it (an output, say, or a digital source).
        case noChannel
        /// It carries the same Mixer channel as an earlier USB Channel, whose preamp already moved.
        case sameChannel(asUSBChannel: Int)
        /// Its Mixer channel shares a preamp with an earlier USB Channel's (a shared headamp, a stereo link), and that
        /// preamp already moved (#458).
        case samePreamp(asUSBChannel: Int)
    }

    /// Where a USB Channel is in a run, for the progress the sheet shows.
    public enum Phase: Equatable, Sendable {
        /// Waiting for the run to reach it.
        case waiting
        /// Its meters are being read.
        case measuring
        /// Its preamp is moving, or waiting for its turn on the Mixer.
        case adjusting
        /// Finished, with what happened.
        case done(Result)
    }

    /// Told each time a USB Channel in a run moves to another phase.
    public var onPhase: ((Int, Phase) -> Void)?

    /// The linked Mixer's gain control, asked for at every step, as long as it is the Mixer this session's moves (and
    /// so its Undo steps) were made on (#508).
    private let link: SameMixerControl
    private var control: any GainControl { link.control }
    private let rule: AutoGainRule
    private let measure: (Int) async -> Double?
    private let settle: () async -> Void
    /// Told about every gain change made and undone (#450): the Recorder logs it in the Take or the Show.
    private let log: (TakeMetadata.GainChange) -> Void
    /// A level that misses where a gain move should have put it by more than this means the move went elsewhere.
    static let followToleranceDb = 6.0

    private struct LevelDidNotFollow: Error {}
    private struct StoppedForTake: Error {}
    /// The audio stopped while measuring (disarmed, a sample-rate change): nothing to measure (#554).
    private struct AudioStopped: Error {}
    /// Set by `stop()`: no more gain moves in this run.
    private var stopRequested = false

    /// Stops a run under way at once, before its next gain move (a Take started). The channel it was on says so;
    /// channels after it are left alone. Every move made stays for Undo.
    public func stop() {
        stopRequested = true
    }
    /// Every gain step taken, by USB Channel, for Undo.
    public private(set) var steps: [Int: [GainStep]] = [:]
    /// The steps each channel running now has taken, before they join `steps`: another channel's move needs them (#685).
    private var inFlight: [Int: [GainStep]] = [:]
    /// Every setting auto-gain moved and still holds for Undo, on any channel, this run's and earlier runs' (#685).
    private var heldSettings: Set<MixHold.Setting> {
        Set((Array(steps.values) + inFlight.values).joined().flatMap { $0.changes.map(\.setting) })
    }

    /// - Parameters:
    ///   - measure: a USB Channel's Average level now, in dBFS, from the meters; nil when the audio stopped.
    ///   - settle: waits for the meters to follow a gain move before measuring again.
    public convenience init(control: any GainControl, rule: AutoGainRule = AutoGainRule(), measure: @escaping (Int) async -> Double?,
                            settle: @escaping () async -> Void = {}, queue: MixerQueue = MixerQueue(),
                            log: @escaping (TakeMetadata.GainChange) -> Void = { _ in }) {
        self.init(currentControl: { control }, rule: rule, measure: measure, settle: settle, queue: queue, log: log)
    }

    /// - Parameter currentControl: the linked Mixer's gain control now, or nil while the Mixer Link is down or the Armed
    ///   input isn't the linked Mixer. Runs and Undo use whatever it gives at each step, so a reconnect's new driver is
    ///   used, and Undo steps (the Mixer's own values) still put the gain back through it.
    ///   - mixer: which Mixer is linked now, its network name and model; the session keeps to the one linked when it
    ///     was made.
    public init(currentControl: @escaping () -> (any GainControl)?, mixer: @escaping () -> String? = { nil },
                rule: AutoGainRule = AutoGainRule(), measure: @escaping (Int) async -> Double?,
                settle: @escaping () async -> Void = {}, queue: MixerQueue = MixerQueue(),
                log: @escaping (TakeMetadata.GainChange) -> Void = { _ in }) {
        link = SameMixerControl(currentControl: currentControl, mixer: mixer)
        self.log = log
        self.rule = rule
        self.measure = measure
        self.settle = settle
        mixerQueue = queue
        // Clip protection on this Mixer's queue is given what this session still holds for Undo (#686).
        queue.autoGainHeld = { [weak self] in self?.heldSettings ?? [] }
    }

    /// Reads which preamp each channel takes ahead, as the auto-gain sheet opens (#874): a run keeps using it.
    public func readPreamps() async {
        await link.control.readPreamps()
    }

    /// Runs auto-gain on each of `usbChannels` and says what happened to each, in the order asked. The channels are
    /// measured and stepped together: each USB Channel is measured on its own, and each moves its own preamp.
    /// `stop()` halts every channel still moving before its next move.
    public func run(usbChannels: [Int]) async -> [Result] {
        stopRequested = false
        // First, which Mixer channel and preamp each USB Channel moves, so no preamp is moved by two at once.
        var results: [Result?] = []
        var toRun: [(index: Int, usbChannel: Int, channel: Int)] = []
        var done: [Int: Int] = [:]   // Mixer channel -> the USB Channel that moves it
        var donePreamps: [Int: Int] = [:]   // preamp -> the USB Channel that moves it
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
            toRun.append((results.count, usbChannel, channel))
            results.append(nil)
        }
        for result in results.compactMap({ $0 }) { onPhase?(result.usbChannel, .done(result)) }
        for item in toRun { onPhase?(item.usbChannel, .waiting) }
        // Then every channel at once, each in its own Task on the main actor; canceling the run cancels them all.
        // (Stopped during the first pass, nothing has moved yet and none of them runs.)
        let running = stopRequested ? [] : toRun.map { item in
            (item.index, Task {
                let result = await self.runOne(usbChannel: item.usbChannel, channel: item.channel)
                self.onPhase?(item.usbChannel, .done(result))   // as soon as it's done, not in the order asked
                return result
            })
        }
        await withTaskCancellationHandler {
            for (index, task) in running { results[index] = await task.value }
        } onCancel: {
            for (_, task) in running { task.cancel() }
        }
        return results.compactMap { $0 }
    }

    /// Runs the rule on one USB Channel, moving its Mixer channel's preamp.
    private func runOne(usbChannel: Int, channel: Int) async -> Result {
        var taken: [GainStep] = [] {
            didSet { inFlight[usbChannel] = taken }
        }
        defer { inFlight[usbChannel] = nil }
        var expected: Double?   // where the last move should have put the level
        var lastLevel = 0.0
        var limit: MixHold.Limit?   // what limited the latest step, if anything did
        let outcome: AutoGainRule.Outcome
        do {
            outcome = try await rule.run(
                measure: {
                    onPhase?(usbChannel, .measuring)
                    guard let level = await measure(usbChannel) else { throw AudioStopped() }
                    // Our meters measure what's recorded: if the level didn't follow the gain, the wrong preamp moved.
                    if let expected, abs(level - expected) > Self.followToleranceDb { throw LevelDidNotFollow() }
                    lastLevel = level
                    return level
                },
                adjust: { db in
                    onPhase?(usbChannel, .adjusting)
                    let moved: GainStep?
                    do throws(MixerLinkProblem) {
                        // Checked again once it's this channel's turn on the Mixer: a stop while it waited means no move.
                        moved = try await onMixer { () throws(MixerLinkProblem) -> GainStep? in
                            if stopRequested { return nil }
                            // What auto-gain moved and still holds for Undo, on any channel, read once it's this
                            // channel's turn: Mix Hold keeps those end stops (#685).
                            // And what clip protection's turn-downs moved this Take (#686).
                            let live = heldSettings.union(mixerQueue.clipMoved)
                            return try await control.applyMixHold(channel: channel, gainChangeDb: db, scopes: .all, live: live)
                        }
                    } catch {
                        // Stopped partway: what was written is logged and kept for Undo (#450), then the run ends.
                        if case .gainMoveInterrupted(let partial) = error {
                            taken.append(partial)
                            log(GainLog.change(partial, usbChannel: usbChannel, reason: .autoGain))
                        }
                        throw error
                    }
                    guard let step = moved else { throw StoppedForTake() }
                    let applied = step.toGainDb - step.fromGainDb
                    limit = step.limitedBy
                    // A step that moved nothing changed nothing: there's nothing to log or undo. A setting can move
                    // while the gain snaps back to where it was, so that counts as a move.
                    if applied != 0 || step.changes.contains(where: { step.held[$0.setting] ?? $0.toDb != $0.fromDb }) {
                        taken.append(step)
                        log(GainLog.change(step, usbChannel: usbChannel, reason: .autoGain))
                    }
                    expected = lastLevel + applied
                    return applied
                },
                settle: { await settle() }
            )
        } catch is StoppedForTake {
            steps[usbChannel, default: []] += taken
            return .haltedForTake(usbChannel: usbChannel, channel: channel)
        } catch is AudioStopped {
            // Nothing was measured wrong, so nothing is put back: every move made stays for Undo.
            steps[usbChannel, default: []] += taken
            return .skipped(usbChannel: usbChannel, reason: .noSignal)
        } catch is LevelDidNotFollow {
            // Newest first; a step the Mixer wouldn't take back stays for Undo, with every older one, and the
            // result is the Mixer's problem rather than "stopped", which says the gain was put back.
            // A Take that starts meanwhile doesn't stop it (Eric, #663): it puts back the operator's gain, and it is
            // bounded. It undoes only this run's steps on this channel, at most `rule.maxPasses` (one per pass). Each
            // undo is a ramp of 3 dB steps (`rampStepDb`) of Mixer requests, each limited by the driver's reply timeout (OSC, 1.5 s), and a
            // request that times out ends the rollback; each undo first reads the preamp's gain once more (#670). It is one job on the Mixer's queue, so a clip protection
            // turn-down asked for meanwhile writes right after its last undo; one queued behind several channels'
            // rollbacks waits for all of them, first in, first out. The run makes no gain move after a Take started
            // (`stopRequested`).
            var undoProblem: MixerLinkProblem?
            // The body catches every Mixer problem into `undoProblem`, so the `try?` hides nothing.
            _ = try? await onMixer { () throws(MixerLinkProblem) in
                while undoProblem == nil, let step = taken.last {
                    do throws(MixerLinkProblem) {
                        // Not over a preamp something else moved since (a clip turn-down on a shared one, #670).
                        try await control.undo(step, ifUnmoved: true)
                        taken.removeLast()
                        log(GainLog.change(step, usbChannel: usbChannel, reason: .undo, undoing: true))
                    } catch {
                        undoProblem = error
                    }
                }
            }
            steps[usbChannel, default: []] += taken
            if let undoProblem {
                return .error(usbChannel: usbChannel, channel: channel, problem: undoProblem)
            } else {
                return .stopped(usbChannel: usbChannel, channel: channel)
            }
        } catch let problem as MixerLinkProblem {
            steps[usbChannel, default: []] += taken
            return .error(usbChannel: usbChannel, channel: channel, problem: problem)
        } catch {
            steps[usbChannel, default: []] += taken
            return .error(usbChannel: usbChannel, channel: channel, problem: .other(String(describing: error)))
        }
        // Added to any earlier run's steps on this USB Channel, so Undo goes all the way back.
        steps[usbChannel, default: []] += taken
        switch outcome {
        case .onTarget(let level, _, _):
            guard let first = taken.first, let last = taken.last else {
                return .skipped(usbChannel: usbChannel, reason: .alreadyOnTarget(levelDbfs: level))
            }
            return .set(usbChannel: usbChannel, channel: channel, fromGainDb: first.fromGainDb, toGainDb: last.toGainDb, levelDbfs: level)
        case .failed(.noSignal, _):
            return .skipped(usbChannel: usbChannel, reason: .noSignal)
        case .failed(let failure, _):
            let limitedBy: MixHold.Limit? = if case .rangeReached = failure { limit } else { nil }
            return .failed(usbChannel: usbChannel, channel: channel, failure: failure, limitedBy: limitedBy)
        }
    }

    /// One gain move or undo on the Mixer at a time, in the order asked (`MixerQueue`): the Mixer's queue, shared with
    /// clip protection.
    private let mixerQueue: MixerQueue

    private func onMixer<T>(_ body: () async throws(MixerLinkProblem) -> T) async throws(MixerLinkProblem) -> T {
        try await mixerQueue.run(body)
    }

    /// USB Channels with an Undo under way.
    private var undoing: Set<Int> = []

    /// Puts back every gain step taken on `usbChannel`, newest first.
    /// Each step is dropped as soon as it is undone, so when the Mixer stops answering partway the rest stay for
    /// another Undo, and none is undone twice. An Undo asked for while one is under way on the same USB Channel does
    /// nothing: the first one takes back every step.
    /// `stop()` ends it before its next step (a Take started); the steps left stay for another Undo.
    public func undo(usbChannel: Int) async throws(MixerLinkProblem) {
        guard undoing.insert(usbChannel).inserted else { return }
        defer { undoing.remove(usbChannel) }
        stopRequested = false
        while !stopRequested, let step = steps[usbChannel]?.last {
            // Checked again once it's this Undo's turn on the Mixer: a Take that started while it waited stops it.
            let undone = try await onMixer { () throws(MixerLinkProblem) -> Bool in
                if stopRequested { return false }
                try await control.undo(step)
                return true
            }
            guard undone else { return }
            if steps[usbChannel]?.last == step { steps[usbChannel]?.removeLast() }
            log(GainLog.change(step, usbChannel: usbChannel, reason: .undo, undoing: true))
        }
    }

    /// Puts back every gain step of the run.
    public func undoAll() async throws(MixerLinkProblem) {
        for usbChannel in steps.keys.sorted().reversed() { try await undo(usbChannel: usbChannel) }
    }

    /// What Mix Hold moved to keep the mix the same on `usbChannel`, from before its first step still held to now:
    /// one entry per setting, in channel and setting order. Empty once Undo has put every step back.
    public func compensated(usbChannel: Int) -> [TakeMetadata.GainChange.Compensation] {
        var moved: [MixHold.Setting: (fromDb: Double, toDb: Double)] = [:]
        for step in steps[usbChannel] ?? [] {
            for change in step.changes {
                let toDb = step.held[change.setting] ?? change.toDb
                moved[change.setting] = (moved[change.setting]?.fromDb ?? change.fromDb, toDb)
            }
        }
        return moved.filter { $0.value.fromDb != $0.value.toDb }
            .map { TakeMetadata.GainChange.Compensation(channel: $0.key.channel, setting: $0.key.parameter.logName,
                                                         fromDb: $0.value.fromDb, toDb: $0.value.toDb) }
            .sorted { ($0.channel, $0.setting) < ($1.channel, $1.setting) }
    }
}

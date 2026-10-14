import Foundation
import MixerLink
import TakeFile

/// Watches one USB Channel's meter windows for a sustained hot peak (#448): a Peak above -3 dBFS held for about
/// 300 ms. Fed every window `PeakMeters.takeLevels()` gives; a window's length comes from its frames, not the clock.
/// One window at or below -3 doesn't restart the count (vibrato, a bass note's ripple); two in a row do.
/// It also fires on 3 clips within 2 s, counting each run of clipping windows as one clip, so how often the meters
/// are read doesn't change the count. A lone transient or a single clip never fires it.
public struct ClipTrigger: Sendable {
    /// How long the Peak has to stay above `ChannelMeter.hotPeakDbfs`.
    public static let sustainSeconds = 0.3
    /// The most one window counts for: a late read (the app in the background, say) merges many windows into one,
    /// and one transient in it must not look held.
    static let longestWindowSeconds = 0.05

    private let sampleRate: Double
    private var hotSeconds = 0.0
    private var highestDbfs = -Double.infinity
    private var coolWindows = 0
    /// Clips within this many seconds, at least `clipCount` of them, fire.
    public static let clipSeconds = 2.0
    public static let clipCount = 3
    /// Seconds of audio seen so far, by frames.
    private var clock = 0.0
    private var clipTimes: [Double] = []
    private var wasClipping = false

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Takes one meter window. Returns the highest Peak of the episode, in dBFS, when it fires.
    public mutating func observe(_ level: ChannelLevel) -> Double? {
        let dbfs = level.peak > 0 ? 20 * log10(Double(level.peak)) : -Double.infinity
        clock += Double(level.frames) / sampleRate
        let clipping = level.peak >= Recorder.clipLevel
        if clipping && !wasClipping { clipTimes.append(clock) }
        wasClipping = clipping
        clipTimes.removeAll { clock - $0 > Self.clipSeconds }
        if clipTimes.count >= Self.clipCount { return fire(max(highestDbfs, 0)) }
        guard dbfs > ChannelMeter.hotPeakDbfs else {
            coolWindows += 1
            if coolWindows > 1 {
                hotSeconds = 0
                highestDbfs = -.infinity
            }
            return nil
        }
        coolWindows = 0
        hotSeconds += min(Double(level.frames) / sampleRate, Self.longestWindowSeconds)
        highestDbfs = max(highestDbfs, dbfs)
        return hotSeconds >= Self.sustainSeconds ? fire(highestDbfs) : nil
    }

    /// Starts over, as after a gain move.
    public mutating func reset() {
        hotSeconds = 0
        highestDbfs = -.infinity
        coolWindows = 0
        clipTimes = []
    }

    private mutating func fire(_ dbfs: Double) -> Double {
        reset()
        return dbfs
    }
}

/// Automatic clip protection (#448): when a USB Channel's Peak runs hot, turns its preamp down on the Mixer with
/// Mix Hold, so the recording stops clipping and the mix stays the same. Works during a Take too, within limits.
@MainActor
public final class ClipProtection {
    /// Where a move puts the Peak.
    nonisolated public static let targetPeakDbfs = -6.0
    /// The most one move turns a preamp down.
    nonisolated public static let largestStepDb = 6.0
    /// After a move, a Mixer channel is left alone this long, so the meters catch up and one loud song doesn't walk
    /// the preamp down step after step.
    nonisolated public static let restSeconds = 5.0
    /// The most a Mixer channel is turned down in one Take (and between Takes, until the next one starts), so a
    /// fault can't walk a preamp to nothing during a show.
    nonisolated public static let mostPerTakeDb = 12.0

    /// The gain change that brings `peakDbfs` to `targetPeakDbfs`, at most `largestStepDb` down. A clipping window
    /// reads full scale whatever the real level, so a clip always takes the whole 6 dB. In half-dB, the preamp's
    /// resolution, rounded to turn down more; to the hundredth first, so a meter's float noise doesn't add a step.
    nonisolated public static func stepDb(peakDbfs: Double) -> Double {
        let exact = ((targetPeakDbfs - peakDbfs) * 100).rounded() / 100
        return min(0, max(-largestStepDb, (exact * 2).rounded(.down) / 2))
    }

    /// The linked Mixer's gain control, asked for at every move, as long as it is the Mixer the Take started on
    /// (#554, as #508): after a reconnect to that Mixer, the new driver; on another Mixer or with the Link down, nothing
    /// is written, and it tries again after the rest.
    private let link: SameMixerControl
    private var control: any GainControl { link.control }
    private let sampleRate: Double
    /// One job on the Mixer at a time in each lane (#554), shared with whatever else moves this Mixer's gain.
    private let queue: MixerQueue
    /// Told about every gain change (#450): the Recorder logs it in the Take, with a Marker, or in the Show.
    private let log: (TakeMetadata.GainChange) -> Void
    /// One trigger per USB Channel, by index (USB Channel 1 at 0).
    private var triggers: [ClipTrigger] = []
    /// Seconds of audio read so far, by frames.
    private var clock = 0.0
    /// When each preamp last moved, by `GainControl.preamp(ofChannel:)` (#458): two Mixer channels on one preamp,
    /// a shared X32 headamp or a stereo-linked pair, are one preamp here.
    private var lastMove: [Int: Double] = [:]
    /// When a move was last refused because the Mixer Link was down or on another Mixer: none is tried again until the
    /// rest has passed, as after a Mixer that didn't answer.
    private var refusedAt: Double?
    /// How far each preamp has been turned down since the Take started.
    private var turnedDown: [Int: Double] = [:]

    public convenience init(
        control: any GainControl, sampleRate: Double, queue: MixerQueue = MixerQueue(),
        log: @escaping (TakeMetadata.GainChange) -> Void = { _ in }
    ) {
        self.init(currentControl: { control }, mixer: { nil }, sampleRate: sampleRate, queue: queue, log: log)
    }

    /// - Parameters:
    ///   - currentControl: the linked Mixer's gain control now, or nil while the Mixer Link is down.
    ///   - mixer: which Mixer is linked now ("FOH · XR18"), or nil while the Link is down. The one linked now is the
    ///     one this protects; on any other, it writes nothing.
    ///   - queue: the Mixer's queue every turn-down waits its turn in, in its lane.
    public init(
        currentControl: @escaping () -> (any GainControl)?, mixer: @escaping () -> String?, sampleRate: Double,
        queue: MixerQueue = MixerQueue(), log: @escaping (TakeMetadata.GainChange) -> Void = { _ in }
    ) {
        link = SameMixerControl(currentControl: currentControl, mixer: mixer)
        self.sampleRate = sampleRate
        self.queue = queue
        self.log = log
    }

    /// Set by `stop()`: no move starts after it.
    private var stopped = false

    /// A Take started: each channel may be turned down `mostPerTakeDb` again.
    public func takeStarted() {
        turnedDown = [:]
    }

    /// The Take ended, or protection was switched off: a move still waiting on the Mixer doesn't start.
    public func stop() {
        stopped = true
    }

    /// Mixer channels with a turn-down started and not yet done: one that runs hot again meanwhile is skipped, so a slow
    /// Mixer holds at most one pending turn-down per Mixer channel (#554).
    private var pending: Set<Int> = []

    /// Takes one meter read and waits for any turn-down it starts.
    public func observe(_ levels: [ChannelLevel]) async {
        await meters(levels)?.value
    }

    /// Takes one meter read, every USB Channel's window (USB Channel 1 first), at once (#554): every trigger takes its
    /// window now, and a read where a channel runs hot starts one task turning its preamp down. Returns that task.
    @discardableResult
    public func meters(_ levels: [ChannelLevel]) -> Task<Void, Never>? {
        guard !stopped else { return nil }
        if triggers.count != levels.count { triggers = Array(repeating: ClipTrigger(sampleRate: sampleRate), count: levels.count) }
        clock += Double(levels.map(\.frames).max() ?? 0) / sampleRate
        // Every trigger takes its window before any move waits on the Mixer: the next read can arrive during that
        // wait (and a disarm can leave no channels), so nothing below touches `triggers`.
        let fired = levels.indices.compactMap { index in triggers[index].observe(levels[index]).map { (usbChannel: index + 1, peak: $0) } }
        // Every preamp behind a channel that fired is read at once, then which ones move is settled in USB Channel
        // order (so of two channels on one preamp the lower moves it, as before), then they all move at once (#554):
        // a second hot preamp doesn't wait for the first's ramp.
        guard !fired.isEmpty else { return nil }
        if let refusedAt, clock - refusedAt < Self.restSeconds { return nil }
        // Nothing is written to, or logged for, another Mixer, or with the Link down (#554, as #508).
        if link.isRefusing {
            refusedAt = clock
            return nil
        }
        var targets: [(usbChannel: Int, channel: Int, peak: Double)] = []
        for (usbChannel, peak) in fired {
            if let channel = control.channel(forUSBChannel: usbChannel), !pending.contains(channel) {
                targets.append((usbChannel, channel, peak))
            }
        }
        guard !targets.isEmpty else { return nil }
        pending.formUnion(targets.map(\.channel))
        return Task { await turnDown(targets) }
    }

    /// Mixer channels whose turn-down is done, or was never made: they may turn down again.
    private func release(_ channels: Set<Int>) {
        pending.subtract(channels)
    }

    /// Reads the preamp and lane behind each channel that fired, settles which move, and moves them.
    private func turnDown(_ targets: [(usbChannel: Int, channel: Int, peak: Double)]) async {
        var preamps = [Int](repeating: 0, count: targets.count)
        var lanes = [Int?](repeating: nil, count: targets.count)
        await withTaskGroup(of: (Int, Int, Int?).self) { group in
            for (index, target) in targets.enumerated() {
                group.addTask {
                    async let preamp = self.preamp(ofChannel: target.channel)
                    async let lane = self.lane(ofChannel: target.channel)
                    return (index, await preamp, await lane)
                }
            }
            for await (index, preamp, lane) in group {
                preamps[index] = preamp
                lanes[index] = lane
            }
        }
        // The wait for the Mixer can outlast the Take.
        guard !stopped else {
            release(Set(targets.map(\.channel)))
            return
        }
        var moves: [(usbChannel: Int, channel: Int, preamp: Int, lane: Lane, gainChangeDb: Double)] = []
        for (index, target) in targets.enumerated() {
            let preamp = preamps[index]
            guard lastMove[preamp].map({ clock - $0 >= Self.restSeconds }) ?? true else { continue }
            let left = Self.mostPerTakeDb - (turnedDown[preamp] ?? 0)
            guard left > 0 else { continue }
            lastMove[preamp] = clock
            let lane = lanes[index].map(Lane.pair) ?? .preamp(preamp)
            moves.append((target.usbChannel, target.channel, preamp, lane, max(-left, Self.stepDb(peakDbfs: target.peak))))
        }
        release(Set(targets.map(\.channel)).subtracting(moves.map(\.channel)))
        // Moves in one lane go one after the other, in USB Channel order (#554): the Mixer mirrors fader and sends between
        // the strips of a linked pair, so two moves at once could both rewrite one setting. Lanes move at once.
        // Known gap: on an X32 a move also compensates the other channels on its headamp (#473), so a channel sharing a
        // headamp with one strip of a linked pair can still move alongside that pair. Rare; left for now.
        await withTaskGroup(of: Void.self) { group in
            for lane in Dictionary(grouping: moves, by: { $0.lane }).values {
                group.addTask { await self.move(lane) }
            }
        }
    }

    /// Moves one lane's turn-downs one after the other. A lane done frees its channels, though another lane from the same
    /// read still waits on the Mixer.
    private func move(_ lane: [(usbChannel: Int, channel: Int, preamp: Int, lane: Lane, gainChangeDb: Double)]) async {
        for move in lane {
            await turnDown(move.usbChannel, channel: move.channel, preamp: move.preamp, lane: move.lane, by: move.gainChangeDb)
        }
        release(Set(lane.map(\.channel)))
    }

    /// Moves in one lane go one after the other: a strip-linked pair (by its first channel), or else one preamp.
    private enum Lane: Hashable {
        case pair(Int)
        case preamp(Int)
    }

    /// The lane Mixer channel `channel` moves in, or nil for its own preamp's, as when the Mixer doesn't answer.
    private func lane(ofChannel channel: Int) async -> Int? {
        (try? await control.lane(ofChannel: channel)) ?? nil
    }

    /// The preamp behind Mixer channel `channel`. The Mixer not answering is no reason to skip protecting: the channel
    /// then stands for its own preamp, negative so it can't be mistaken for a preamp number.
    private func preamp(ofChannel channel: Int) async -> Int {
        ((try? await control.preamp(ofChannel: channel)) ?? nil) ?? -channel
    }

    /// Turns `channel`'s preamp down by `gainChangeDb` (negative) with Mix Hold, in its lane of the Mixer's queue, and
    /// logs what moved.
    private func turnDown(_ usbChannel: Int, channel: Int, preamp: Int, lane: Lane, by gainChangeDb: Double) async {
        // A lane's earlier move can outlast the Take.
        guard !stopped else { return }
        let step: GainStep
        do throws(MixerLinkProblem) {
            // So can the wait in the queue.
            guard let moved = try await queue.run(lane: lane, { () throws(MixerLinkProblem) -> GainStep? in
                guard !stopped else { return nil }
                return try await control.applyMixHold(channel: channel, gainChangeDb: gainChangeDb, scopes: .all)
            }) else { return }
            step = moved
        } catch {
            // Stopped partway: whatever was written still counts and is logged (#450); otherwise nothing moved.
            guard case .gainMoveInterrupted(let partial) = error else { return }
            step = partial
        }
        // At its lowest gain, or Mix Hold out of range: nothing moved, so nothing to log or Mark.
        guard step.toGainDb < step.fromGainDb else { return }
        turnedDown[preamp, default: 0] += step.fromGainDb - step.toGainDb
        log(GainLog.change(step, usbChannel: usbChannel, reason: .clipProtection))
    }
}

/// Whether clip protection (#448) is on: off until the operator switches it on in Settings.
public enum ClipProtectionSetting {
    /// The key it is stored under.
    public static let key = "clipProtection"

    /// Offered where auto-gain is (`AutoGainAvailability`, Debug builds for now): it moves the same preamps through
    /// the same driver, which hasn't yet run on a real desk with real audio.
    public static func isOffered(isDebugBuild: Bool = LaunchFlags.isDebugBuild) -> Bool {
        AutoGainAvailability.isAvailable(isDebugBuild: isDebugBuild)
    }

    public static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    public static func save(_ isOn: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isOn, forKey: key)
    }
}

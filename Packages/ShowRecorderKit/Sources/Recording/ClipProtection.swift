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

    private let control: any GainControl
    private let sampleRate: Double
    /// Told about every gain change (#450): the Recorder logs it in the Take, with a Marker, or in the Show.
    private let log: (TakeMetadata.GainChange) -> Void
    /// One trigger per USB Channel, by index (USB Channel 1 at 0).
    private var triggers: [ClipTrigger] = []
    /// Seconds of audio read so far, by frames.
    private var clock = 0.0
    /// When each preamp last moved, by `GainControl.preamp(ofChannel:)` (#458): two Mixer channels on one preamp,
    /// a shared X32 headamp or a stereo-linked pair, are one preamp here.
    private var lastMove: [Int: Double] = [:]
    /// How far each preamp has been turned down since the Take started.
    private var turnedDown: [Int: Double] = [:]

    public init(control: any GainControl, sampleRate: Double, log: @escaping (TakeMetadata.GainChange) -> Void = { _ in }) {
        self.control = control
        self.sampleRate = sampleRate
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

    /// Takes one meter read, every USB Channel's window (USB Channel 1 first), and turns down any preamp whose
    /// channel runs hot.
    public func observe(_ levels: [ChannelLevel]) async {
        guard !stopped else { return }
        if triggers.count != levels.count { triggers = Array(repeating: ClipTrigger(sampleRate: sampleRate), count: levels.count) }
        clock += Double(levels.map(\.frames).max() ?? 0) / sampleRate
        // Every trigger takes its window before any move waits on the Mixer: the next read can arrive during that
        // wait (and a disarm can leave no channels), so nothing below touches `triggers`.
        let fired = levels.indices.compactMap { index in triggers[index].observe(levels[index]).map { (usbChannel: index + 1, peak: $0) } }
        for (usbChannel, peak) in fired {
            guard let channel = control.channel(forUSBChannel: usbChannel) else { continue }
            // The Mixer not answering here is no reason to skip protecting: the channel then stands for its own preamp,
            // negative so it can't be mistaken for a preamp number.
            let preamp = ((try? await control.preamp(ofChannel: channel)) ?? nil) ?? -channel
            // The wait for the Mixer can outlast the Take.
            guard !stopped else { return }
            guard lastMove[preamp].map({ clock - $0 >= Self.restSeconds }) ?? true else { continue }
            let left = Self.mostPerTakeDb - (turnedDown[preamp] ?? 0)
            guard left > 0 else { continue }
            lastMove[preamp] = clock
            let step: GainStep
            do throws(MixerLinkProblem) {
                step = try await control.applyMixHold(channel: channel, gainChangeDb: max(-left, Self.stepDb(peakDbfs: peak)), scopes: .all)
            } catch {
                // Stopped partway: whatever was written still counts and is logged (#450); otherwise nothing moved.
                guard case .gainMoveInterrupted(let partial) = error else { continue }
                step = partial
            }
            // At its lowest gain, or Mix Hold out of range: nothing moved, so nothing to log or Mark.
            guard step.toGainDb < step.fromGainDb else { continue }
            turnedDown[preamp, default: 0] += step.fromGainDb - step.toGainDb
            log(GainLog.change(step, usbChannel: usbChannel, reason: .clipProtection))
        }
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

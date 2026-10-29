import Foundation
import MixerLink
import Observation
import TakeFile

/// Gain on the linked Mixer (#554): auto-gain between Takes and clip protection during them, through one `MixerQueue`,
/// so their moves and Undo on one Mixer never overlap.
///
/// Auto-gain's state on the record screen (#155): what each USB Channel's run did, which are running, and the steps to
/// Undo. The record screen keeps it, so closing the sheet loses nothing and Undo is still there when it opens again.
/// Locked while a Take runs: no gain moves during a Take, and a Take that starts mid-run stops it at once.
///
/// Clip protection (#448): only during a Take (Eric, 2026-10-13), and only when switched on (off by default).
/// It follows Takes (`TakeSequencer.events`) and takes every meter read the screen takes.
@MainActor
@Observable
public final class MixerGain {
    /// What happened to each USB Channel, last run or Undo.
    public private(set) var results: [Int: AutoGainSession.Result] = [:]
    /// USB Channels with a run or an Undo under way.
    public private(set) var running: Set<Int> = []
    /// Where each USB Channel of the run under way is: waiting, measuring, adjusting. Empty when no run is going.
    public private(set) var phases: [Int: AutoGainSession.Phase] = [:]
    /// How far a run has got: channels done of all it was asked to run.
    public struct Progress: Equatable, Sendable {
        public var done: Int
        public var total: Int
        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }
        /// "7 of 16 channels done".
        public var text: String { "\(done) of \(total) \(total == 1 ? "channel" : "channels") done" }
    }
    /// The run under way, or nil.
    public var progress: Progress? {
        phases.isEmpty ? nil : Progress(done: phases.values.filter { if case .done = $0 { true } else { false } }.count,
                                        total: phases.count)
    }
    /// Runs finished so far, and how many channels the last one had: the sheet tells VoiceOver when one finishes.
    public private(set) var finishedRuns = 0
    public private(set) var lastRunTotal = 0
    /// A Take is running: nothing may move a preamp.
    public private(set) var isTakeRunning = false
    /// The session on the linked Mixer, made at the first run and kept for Undo.
    public private(set) var session: AutoGainSession?
    /// Whether the recorder is recording now. Read on every run and Undo, so a Take that has started is respected
    /// before its event arrives; and on every meter read, so a window read after the recorder stopped, before the
    /// Take's end arrives, is left alone.
    @ObservationIgnored public var isRecording: () -> Bool = { false }
    /// The linked Mixer's network name now, nil while the Mixer Link is down. Undo belongs to the Mixer it was made on
    /// (#508): its steps are that Mixer's values, so on another Mixer it is dropped, never written.
    @ObservationIgnored public var mixerName: () -> String? = { nil }
    /// The Mixer the session's Undo steps were made on.
    @ObservationIgnored private var sessionMixer: String?
    /// The Mixer's one queue, given to every session and clip protection made here: auto-gain's moves and Undo go one
    /// at a time on the whole Mixer, clip protection's turn-downs one at a time per preamp lane.
    private let queue = MixerQueue()
    /// A new session on the linked Mixer moving gain through the given queue, or nil when there is none. Set by
    /// whoever owns this.
    @ObservationIgnored public var makeSession: (MixerQueue) -> AutoGainSession?
    /// Whether clip protection is switched on, read when each Take starts; it protects only where it is offered.
    @ObservationIgnored public var isClipProtectionOn: () -> Bool = { ClipProtectionSetting.isOn() }
    /// The Mixer session the Gain button follows; nil until whoever owns this sets it.
    @ObservationIgnored public var mixer: MixerSession?
    /// Whether this is a Debug build: clip protection and X32 auto-gain are offered there and in TestFlight.
    @ObservationIgnored public var isDebugBuild = LaunchFlags.isDebugBuild
    /// Which App Store environment this build came through, nil until StoreKit has answered: TestFlight offers clip
    /// protection and X32 auto-gain.
    @ObservationIgnored public var environment: () -> DistributionEnvironment? = { DemoSignalAvailability.environment }
    /// Clip protection on the linked Mixer moving gain through the given queue, or nil when it can't set gain.
    @ObservationIgnored public var makeProtection: (MixerQueue) -> ClipProtection? = { _ in nil }
    /// Whether the plan now includes auto-gain (`License.allowsAutoGain`, #705); it runs between Takes, so it is read live.
    @ObservationIgnored public var allowsAutoGain: () -> Bool = { true }
    /// The allowance the starting Take was frozen with (#705); nil allows everything, as it does for a Take.
    @ObservationIgnored public var takeAllowance: () -> TakeAllowance? = { nil }
    /// Protecting the running Take; nil between Takes.
    @ObservationIgnored public private(set) var protection: ClipProtection?

    public init(makeSession: @escaping (MixerQueue) -> AutoGainSession? = { _ in nil }) {
        self.makeSession = makeSession
    }

    /// Whether the record screen shows the Gain button (#155): while an X Air or X32 is Ready (`AutoGainAvailability`).
    /// When auto-gain can't run (a Take, no Mixer Link, a Mixer whose gain can't be set), the
    /// button stays and its sheet says why (`autoGainUnavailable`) instead of the button disappearing.
    public var offersAutoGain: Bool {
        AutoGainAvailability.isOffered(available: AutoGainAvailability.isAvailable(isDebugBuild: isDebugBuild, environment: environment()),
                                       mixerLinkOffered: mixer?.isOffered ?? false)
    }

    /// Why auto-gain can't run right now, said on its sheet while the Gain button stays; nil when it can.
    /// An X32's gain is set only where `X32AutoGainAvailability` allows it.
    public var autoGainUnavailable: AutoGainAvailability.Unavailable? {
        let isConnecting = if case .connecting = mixer?.status { true } else { false }
        let canSetGain = mixer?.gainControl != nil && setsThisFamilysGain
        return AutoGainAvailability.whyNot(hasMixerLink: mixer?.identity != nil, isConnecting: isConnecting,
                                           canSetGain: canSetGain, isRecording: isRecording(),
                                           otherMixer: mixer?.otherMixerLinked?.nameAndModel, allowed: allowsAutoGain())
    }

    /// False on an X32 where `X32AutoGainAvailability` doesn't allow it; true for any other family.
    private var setsThisFamilysGain: Bool {
        mixer?.family != .x32 || X32AutoGainAvailability.isAvailable(isDebugBuild: isDebugBuild, environment: environment())
    }

    /// Whether Settings offers clip protection's switch (`ClipProtectionSetting.isOffered`).
    public var offersClipProtection: Bool { ClipProtectionSetting.isOffered(isDebugBuild: isDebugBuild, environment: environment()) }

    /// The sheet's buttons wait: a Take is running, or a run or Undo is under way.
    public var isLocked: Bool { isTakeRunning || isRecording() || !running.isEmpty }

    /// The auto-gain sheet opened: reads the Mixer's channel-to-preamp routing now, and the runs of this visit use it (#874).
    /// Not during a Take, and not without a Pro plan, as for a run.
    public func prepare() async {
        guard !isLocked, allowsAutoGain(), let session = session ?? makeSession(queue) else { return }
        if self.session == nil { sessionMixer = mixerName() }
        self.session = session
        await session.readPreamps()
    }

    /// Runs auto-gain on `usbChannels`. Not during a Take, and not while another run or Undo is under way.
    public func run(_ usbChannels: [Int]) async {
        dropUndoForAnotherMixer()
        // Auto-gain is Pro (#705); Undo of an earlier run stays open to everyone.
        guard !isLocked, allowsAutoGain(), setsThisFamilysGain, let session = session ?? makeSession(queue) else { return }
        if self.session == nil { sessionMixer = mixerName() }
        self.session = session
        running.formUnion(usbChannels)
        for usb in usbChannels { phases[usb] = .waiting }
        session.onPhase = { [weak self] usb, phase in
            self?.phases[usb] = phase
            // Each result shows as soon as its channel is done, not when the whole run is.
            if case .done(let result) = phase { self?.results[usb] = result }
        }
        for result in await session.run(usbChannels: usbChannels) { results[result.usbChannel] = result }
        session.onPhase = nil
        lastRunTotal = phases.count
        finishedRuns += 1
        phases = [:]
        running.subtract(usbChannels)
    }

    /// Puts `usbChannel`'s gain back. Locked like a run while it waits on the Mixer; if the Mixer stops answering, the
    /// row says so and Undo stays offered for what's left. Not during a Take.
    public func undo(_ usbChannel: Int) async {
        dropUndoForAnotherMixer()
        guard !isLocked, let session else { return }
        let channel = session.steps[usbChannel]?.first?.channel ?? usbChannel
        running.insert(usbChannel)
        defer { running.remove(usbChannel) }
        do throws(MixerLinkProblem) {
            try await session.undo(usbChannel: usbChannel)
            // A Take that started partway stopped it: what's left stays for Undo after the Take.
            results[usbChannel] = canUndo(usbChannel) ? .haltedForTake(usbChannel: usbChannel, channel: channel) : nil
        } catch {
            results[usbChannel] = .error(usbChannel: usbChannel, channel: channel, problem: error)
        }
    }

    /// Puts every USB Channel's gain back, newest first.
    public func undoAll() async {
        guard let session else { return }
        for usb in session.steps.keys.sorted().reversed() where session.steps[usb]?.isEmpty == false {
            await undo(usb)
        }
    }

    /// Follows Takes (`TakeSequencer.events`): a Take that starts stops any run at once, locks auto-gain until it ends
    /// and turns clip protection on (when switched on); one that ends turns clip protection off.
    public func handle(_ event: TakeEvent) {
        switch event {
        case .takeStarted:
            isTakeRunning = true
            session?.stop()
            // A start while one is running must not leave the old protection live beside the new (#695).
            protection?.stop()
            // Clip protection is Pro (#705): judged from the Take's allowance, frozen at its press.
            let allowed = takeAllowance()?.clipProtection ?? true
            protection = offersClipProtection && isClipProtectionOn() && allowed ? makeProtection(queue) : nil
            protection?.takeStarted()
        case .takeEnded:
            isTakeRunning = false
            protection?.stop()
            protection = nil
        default:
            break
        }
    }

    /// Clip protection switched off in Settings: stops at once, mid-Take too, so the operator can always stop it.
    public func switchedOff() {
        protection?.stop()
        protection = nil
    }

    /// One meter read, every USB Channel's window (USB Channel 1 first), waiting for any turn-down it starts. Nothing
    /// between Takes. Only tests use it; the record screen calls `meters(_:)`.
    public func observe(_ levels: [ChannelLevel]) async {
        guard isRecording() else { return }
        await protection?.observe(levels)
    }

    /// The same, at once (#554): a turn-down it starts runs on its own, so the meters never wait on the Mixer.
    @discardableResult
    public func meters(_ levels: [ChannelLevel]) -> Task<Void, Never>? {
        guard let protection, isRecording() else { return nil }
        return protection.meters(levels)
    }

    public func canUndo(_ usbChannel: Int) -> Bool {
        !isLinkedToAnotherMixer && session?.steps[usbChannel]?.isEmpty == false
    }

    public var canUndoAll: Bool { !isLinkedToAnotherMixer && session?.steps.values.contains { !$0.isEmpty } == true }

    /// What the sheet says when Undo was made on a Mixer that isn't the one linked now.
    public var notice: String? {
        guard isLinkedToAnotherMixer, let sessionMixer else { return nil }
        return "Undo was for another mixer (\(sessionMixer)), so it's gone."
    }

    /// The Mixer Link is up on a Mixer other than the one the Undo steps were made on. Down, it isn't: the same Mixer
    /// may come back.
    private var isLinkedToAnotherMixer: Bool {
        guard session != nil, let made = sessionMixer, let now = mixerName() else { return false }
        return now != made
    }

    /// Drops the session, its results and Undo when they belong to another Mixer, so a run starts fresh here.
    private func dropUndoForAnotherMixer() {
        guard isLinkedToAnotherMixer else { return }
        session = nil
        results = [:]
        sessionMixer = nil
    }

    /// What Mix Hold moved to keep the mix the same on `usbChannel`, in plain words; nil when nothing did, or once Undo
    /// has put it back.
    public func compensationSummary(_ usbChannel: Int) -> String? {
        guard let session, let channel = session.steps[usbChannel]?.first?.channel else { return nil }
        return Self.compensationSummary(session.compensated(usbChannel: usbChannel), channel: channel)
    }

    /// In plain words. Mix Hold moves every setting by the same amount, so that's one line: "To keep the mix: fader,
    /// 6 sends and 2 thresholds moved -25.0 dB". When the amounts differ (a setting reached its end), each is listed:
    /// "fader -80.0 to -90.0 dB, send 3 +5.0 to -20.0 dB". A setting on another channel (one keyed from this one)
    /// names its channel.
    static func compensationSummary(_ moved: [TakeMetadata.GainChange.Compensation], channel: Int) -> String? {
        guard let first = moved.first else { return nil }
        func name(_ change: TakeMetadata.GainChange.Compensation) -> String {
            change.channel == channel ? change.setting : "channel \(change.channel)'s \(change.setting)"
        }
        let amount = first.toDb - first.fromDb
        guard moved.allSatisfy({ abs(($0.toDb - $0.fromDb) - amount) < 0.05 }) else {
            let parts = moved.map { String(format: "%@ %+.1f to %+.1f dB", name($0), $0.fromDb, $0.toDb) }
            return "To keep the mix: " + parts.joined(separator: ", ")
        }
        let own = moved.filter { $0.channel == channel }
        let sends = own.filter { $0.setting.hasPrefix("send ") }
        let thresholds = own.filter { $0.setting.hasSuffix("threshold") }
        func counted(_ group: [TakeMetadata.GainChange.Compensation], _ plural: String) -> [String] {
            group.count > 1 ? ["\(group.count) \(plural)"] : group.map(\.setting)
        }
        let parts = own.filter { $0.setting == "fader" }.map(\.setting)
            + own.filter { $0.setting != "fader" && !sends.contains($0) && !thresholds.contains($0) }.map(\.setting)
            + counted(sends, "sends") + counted(thresholds, "thresholds")
            + moved.filter { $0.channel != channel }.map(name)
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts[0]
        return "To keep the mix: " + list + String(format: " moved %+.1f dB", amount)
    }
}

extension AutoGainSession.Result {
    /// The USB Channel the result is for.
    public var usbChannel: Int {
        switch self {
        case .set(let usb, _, _, _, _), .skipped(let usb, _), .failed(let usb, _, _, _), .stopped(let usb, _),
             .error(let usb, _, _), .haltedForTake(let usb, _): usb
        }
    }
}

extension AutoGainSession.Phase {
    /// Where a channel is, in plain words, for its row: nil once it's done, when the row shows its result.
    public var label: String? {
        switch self {
        case .waiting: "Waiting…"
        case .measuring: "Listening…"
        case .adjusting: "Setting the gain…"
        case .done: nil
        }
    }
}

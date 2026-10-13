import Foundation
import MixerLink
import Observation
import TakeFile

/// Auto-gain's state on the record screen (#155): what each USB Channel's run did, which are running, and the steps to
/// Undo. The record screen keeps it, so closing the sheet loses nothing and Undo is still there when it opens again.
/// Locked while a Take runs: no gain moves during a Take, and a Take that starts mid-run stops it at once.
@MainActor
@Observable
public final class AutoGainPanel {
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
    /// before its event arrives.
    @ObservationIgnored public var isRecording: () -> Bool = { false }
    /// A new session on the linked Mixer, or nil when there is none. Set by whoever owns the panel.
    @ObservationIgnored public var makeSession: () -> AutoGainSession?

    public init(makeSession: @escaping () -> AutoGainSession? = { nil }) {
        self.makeSession = makeSession
    }

    /// The sheet's buttons wait: a Take is running, or a run or Undo is under way.
    public var isLocked: Bool { isTakeRunning || isRecording() || !running.isEmpty }

    /// Runs auto-gain on `usbChannels`. Not during a Take, and not while another run or Undo is under way.
    public func run(_ usbChannels: [Int]) async {
        guard !isLocked, let session = session ?? makeSession() else { return }
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

    /// Follows Takes (`TakeSequencer.events`): a Take that starts stops any run at once and locks the panel until it ends.
    public func handle(_ event: TakeEvent) {
        switch event {
        case .takeStarted:
            isTakeRunning = true
            session?.stop()
        case .takeEnded:
            isTakeRunning = false
        default:
            break
        }
    }

    public func canUndo(_ usbChannel: Int) -> Bool { session?.steps[usbChannel]?.isEmpty == false }

    public var canUndoAll: Bool { session?.steps.values.contains { !$0.isEmpty } == true }

    /// What Re-Gain moved to keep the mix the same on `usbChannel`, in plain words; nil when nothing did, or once Undo
    /// has put it back.
    public func compensationSummary(_ usbChannel: Int) -> String? {
        guard let session, let channel = session.steps[usbChannel]?.first?.channel else { return nil }
        return Self.compensationSummary(session.compensated(usbChannel: usbChannel), channel: channel)
    }

    /// In plain words. Re-Gain moves every setting by the same amount, so that's one line: "To keep the mix: fader,
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

import MixerLink
import Observation

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
        for result in await session.run(usbChannels: usbChannels) { results[result.usbChannel] = result }
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

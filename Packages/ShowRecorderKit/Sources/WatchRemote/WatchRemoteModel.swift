import Foundation
import Observation

/// How the watch reaches the iPhone (WatchConnectivity in the app; a fake in tests).
@MainActor
public protocol WatchLinkTransport: AnyObject {
    /// Whether the iPhone can take a message now.
    var isReachable: Bool { get }
    /// Sends a command now, never later; `reply` gets the iPhone's answer, or nil when it didn't arrive.
    func send(_ command: WatchCommand, reply: @escaping @MainActor (WatchReply?) -> Void)
}

/// The watch's side of the remote (#100): what it shows, and each command pending until the iPhone confirms it.
/// With no live link it shows the last status as last known, never as live, and a command fails at once rather than
/// waiting to be sent.
@MainActor
@Observable
public final class WatchRemoteModel {
    public enum Display: Equatable {
        /// Just raised: the link comes back when the app is in front, so give it a moment before saying no link.
        case connecting
        case noLink
        case status(WatchStatus)
        /// No live link, but the iPhone sent this before (by application context, which arrives in the background): it
        /// is likely still true, so show it, clearly not live, with its age. Commands wait for a live link (#737).
        case lastKnown(WatchStatus)
    }

    public enum CommandState: Equatable {
        case pending
        case confirmed
        case failed(String)
        /// Sent, but no answer came back: it may or may not have happened.
        case unconfirmed
    }

    public enum Haptic: Equatable {
        /// A light tap: the Marker is in.
        case markerConfirmed
        /// Something needs attention.
        case problem
    }

    public static let noLinkText = "No link to iPhone"
    public static let openPhoneText = "Open ShowRecorder on your iPhone"
    public static let tooLateText = "Too late: the link dropped"
    public static let unconfirmedText = "Not confirmed: check the iPhone"
    /// How long a raised wrist shows Connecting before it says no link.
    static let connectingSeconds: TimeInterval = 3
    /// How long a command shows Sending before it's unconfirmed (WatchConnectivity can take far longer to give up).
    static let sendTimeoutSeconds: TimeInterval = 5

    /// The last status from the iPhone.
    public private(set) var status: WatchStatus?
    public private(set) var isReachable: Bool
    /// Where each kind of command stands, last one sent.
    public private(set) var commands: [WatchCommand.Kind: CommandState] = [:]
    /// Told when the wrist should tap.
    @ObservationIgnored public var haptic: (Haptic) -> Void = { _ in }

    @ObservationIgnored private let link: any WatchLinkTransport
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let after: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    /// Set when the app comes to the front, until a status arrives or a few seconds pass.
    private var connecting = false
    /// Whether `status` came while the link was live, or since it last came back: only then is it shown as live.
    private var statusIsLive = false
    @ObservationIgnored private var connectingSince = 0
    /// The latest command of each kind: only its answer sets what shows.
    @ObservationIgnored private var latest: [WatchCommand.Kind: UUID] = [:]
    /// Problems already tapped on the wrist, kept across a dropped link so they don't tap again.
    @ObservationIgnored private var toldProblems: Set<WatchStatus.Problem> = []

    /// - Parameter after: runs work after a delay (a fake clock in tests).
    public init(link: any WatchLinkTransport, now: @escaping () -> Date = Date.init,
                after: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = WatchRemoteModel.afterDelay) {
        self.link = link
        self.now = now
        self.after = after
        isReachable = link.isReachable
    }

    public nonisolated static func afterDelay(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }

    public var display: Display {
        guard let status else { return connecting ? .connecting : .noLink }
        return isReachable && statusIsLive ? .status(status) : .lastKnown(status)
    }

    /// The app came to the front (a raised wrist): show Connecting for a moment while the link comes back.
    public func appBecameActive() {
        connecting = true
        connectingSince += 1
        let attempt = connectingSince
        after(Self.connectingSeconds) { [weak self] in
            guard let self, connectingSince == attempt else { return }
            connecting = false
        }
    }

    /// Start needs the iPhone Armed: it can't open the mic from the background.
    public var canStart: Bool {
        guard case .status(let status) = display, case .armed = status.state else { return false }
        return true
    }

    public func received(_ new: WatchStatus) {
        if new.problems.contains(where: { !toldProblems.contains($0) }) { haptic(.problem) }
        toldProblems = Set(new.problems)
        status = new
        statusIsLive = isReachable
        connecting = false
    }

    /// A link that drops or comes back makes the last status last known: it shows as live again only when the iPhone
    /// says what's true now.
    public func reachabilityChanged() {
        let was = isReachable
        isReachable = link.isReachable
        if isReachable != was { statusIsLive = false }
    }

    public func send(_ kind: WatchCommand.Kind) {
        guard isReachable else {
            commands[kind] = .failed(Self.noLinkText)
            return
        }
        if kind == .start, !canStart {
            commands[kind] = .failed(Self.openPhoneText)
            return
        }
        commands[kind] = .pending
        // Stamped with the watch's own clock: a paired iPhone and watch keep the same time, and the iPhone allows a few
        // seconds either way. A status's time says when it was sent, not what time it is now (it can arrive late).
        let command = WatchCommand(kind: kind, sentAt: now())
        latest[kind] = command.id
        link.send(command) { [weak self] reply in
            self?.answered(command, reply)
        }
        after(Self.sendTimeoutSeconds) { [weak self] in
            guard let self, latest[kind] == command.id, commands[kind] == .pending else { return }
            commands[kind] = .unconfirmed
        }
    }

    private func answered(_ command: WatchCommand, _ reply: WatchReply?) {
        let kind = command.kind
        guard latest[kind] == command.id else { return }
        switch reply {
        case .done?:
            commands[kind] = .confirmed
            if kind == .marker { haptic(.markerConfirmed) }
        case .refused(let reason)?:
            commands[kind] = .failed(reason)
        case .tooLate?:
            commands[kind] = .failed(Self.tooLateText)
        case nil:
            commands[kind] = .unconfirmed
        }
    }
}

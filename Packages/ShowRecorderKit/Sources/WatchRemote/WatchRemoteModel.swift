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
/// With no link it shows no link, never a stale Recording, and a command fails at once rather than waiting to be sent.
@MainActor
@Observable
public final class WatchRemoteModel {
    public enum Display: Equatable {
        case noLink
        case status(WatchStatus)
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

    /// The last status from the iPhone.
    public private(set) var status: WatchStatus?
    public private(set) var isReachable: Bool
    /// Where each kind of command stands, last one sent.
    public private(set) var commands: [WatchCommand.Kind: CommandState] = [:]
    /// Told when the wrist should tap.
    @ObservationIgnored public var haptic: (Haptic) -> Void = { _ in }

    @ObservationIgnored private let link: any WatchLinkTransport
    @ObservationIgnored private let now: () -> Date
    /// The iPhone's clock less the watch's, from the last status: commands are stamped in the iPhone's time.
    @ObservationIgnored private var clockOffset: TimeInterval = 0
    /// The latest command of each kind: only its answer sets what shows.
    @ObservationIgnored private var latest: [WatchCommand.Kind: UUID] = [:]
    /// Problems already tapped on the wrist, kept across a dropped link so they don't tap again.
    @ObservationIgnored private var toldProblems: Set<WatchStatus.Problem> = []

    public init(link: any WatchLinkTransport, now: @escaping () -> Date = Date.init) {
        self.link = link
        self.now = now
        isReachable = link.isReachable
    }

    public var display: Display {
        guard isReachable, let status else { return .noLink }
        return .status(status)
    }

    /// Start needs the iPhone Armed: it can't open the mic from the background.
    public var canStart: Bool {
        guard case .status(let status) = display, case .armed = status.state else { return false }
        return true
    }

    public func received(_ new: WatchStatus) {
        if new.problems.contains(where: { !toldProblems.contains($0) }) { haptic(.problem) }
        toldProblems = Set(new.problems)
        clockOffset = new.sentAt.timeIntervalSince(now())
        status = new
    }

    /// A dropped link forgets the last status: when it's back, nothing shows until the iPhone says what's true now.
    public func reachabilityChanged() {
        isReachable = link.isReachable
        if !isReachable { status = nil }
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
        let command = WatchCommand(kind: kind, sentAt: now().addingTimeInterval(clockOffset))
        latest[kind] = command.id
        link.send(command) { [weak self] reply in
            self?.answered(command, reply)
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

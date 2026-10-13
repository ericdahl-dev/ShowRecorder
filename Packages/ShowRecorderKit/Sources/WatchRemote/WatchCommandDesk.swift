import Foundation

/// The iPhone's side of the watch remote (#100): runs each command from the wrist once, through the same actions as
/// the record screen's own buttons, so Start meets the same Trial and limit checks there.
///
/// Show-Safe Promise: nothing here acts on its own. A lost link sends nothing, so it can't stop a Take; a command
/// that arrives after the link comes back is too late and is dropped, never replayed.
@MainActor
public final class WatchCommandDesk {
    public struct Actions {
        /// Starts a Take as the Record button does: nil when it started, or why not.
        public var start: () -> String?
        /// Stops the running Take; false when there is none.
        public var stop: () -> Bool
        /// Drops a Marker in the running Take; false when there is none.
        public var marker: () -> Bool

        public init(start: @escaping () -> String?, stop: @escaping () -> Bool, marker: @escaping () -> Bool) {
            self.start = start
            self.stop = stop
            self.marker = marker
        }
    }

    /// How old a command may be when it arrives and still run, in seconds: long enough for a slow link and the two
    /// clocks not quite agreeing, short enough that a tap from before a dropout never lands minutes later.
    public static let maxAge: TimeInterval = 10
    public static let notRecording = "Not recording"
    /// How many recent commands are remembered, to answer a repeat the same way without running it again.
    static let remembered = 256

    private let now: () -> Date
    private let actions: Actions
    private var answered: [UUID: WatchReply] = [:]
    private var order: [UUID] = []

    public init(now: @escaping () -> Date = Date.init, actions: Actions) {
        self.now = now
        self.actions = actions
    }

    public func handle(_ command: WatchCommand) -> WatchReply {
        if let reply = answered[command.id] { return reply }
        let reply = run(command)
        // A command too late is too late again if it comes back, so there's nothing to remember.
        guard reply != .tooLate else { return reply }
        answered[command.id] = reply
        order.append(command.id)
        if order.count > Self.remembered { answered[order.removeFirst()] = nil }
        return reply
    }

    private func run(_ command: WatchCommand) -> WatchReply {
        // Too old, or from the future (stamped wrong): either way, not a tap from just now.
        guard abs(now().timeIntervalSince(command.sentAt)) <= Self.maxAge else { return .tooLate }
        switch command.kind {
        case .start:
            return actions.start().map(WatchReply.refused) ?? .done
        case .stop:
            return actions.stop() ? .done : .refused(Self.notRecording)
        case .marker:
            return actions.marker() ? .done : .refused(Self.notRecording)
        }
    }
}

import Destinations
import Foundation
import WatchRemote

/// What the iPhone tells the Apple Watch remote (#100), from what the record screen already shows: the status chips,
/// the Copies, Dropouts and the Mixer Link. No signals of its own.
public enum WatchStatusMaker {
    /// The running Take, as the watch shows it.
    public struct Take: Equatable, Sendable {
        public var startedAt: Date
        public var title: String
        public var markerCount: Int

        public init(startedAt: Date, title: String, markerCount: Int) {
            self.startedAt = startedAt
            self.title = title
            self.markerCount = markerCount
        }
    }

    /// - Parameters:
    ///   - chips: the status strip's chips; one needing attention for the Device or an available Drive is low space
    ///     (a failed one is a Copy that stopped, told by `copies`).
    ///   - driveAvailable: whether the Drive is there at all (a missing Drive isn't "low on space").
    ///   - copies: the Take's Copies (#550); one that stopped mid-Take is a Copy stopped. Nil: no Take.
    public static func make(
        isArmed: Bool, take: Take?, chips: [StatusChip] = [], driveAvailable: Bool = false,
        copies: TakeCopies? = nil, dropoutCount: Int = 0, mixerDown: Bool = false, now: Date = .now
    ) -> WatchStatus {
        let state: WatchStatus.State = if let take {
            .recording(startedAt: take.startedAt, takeTitle: take.title, markerCount: take.markerCount)
        } else if isArmed {
            .armed
        } else {
            .notArmed
        }
        func needsAttention(_ kind: StatusChip.Kind) -> Bool {
            chips.contains { $0.kind == kind && $0.state == .attention }
        }
        var problems: [WatchStatus.Problem] = []
        if needsAttention(.device) { problems.append(.deviceLowSpace) }
        if driveAvailable, needsAttention(.drive) { problems.append(.driveLowSpace) }
        if !(copies?.stopped.isEmpty ?? true) { problems.append(.copyStopped) }
        if dropoutCount > 0 { problems.append(.gapOrDropout) }
        if mixerDown { problems.append(.mixerLinkLost) }
        return WatchStatus(state: state, problems: problems, sentAt: now)
    }

    /// Today's call with the running words (empty when no Take is running), until the record screen reads
    /// `TakeCopies` itself (#550).
    public static func make(
        isArmed: Bool, take: Take?, chips: [StatusChip] = [], driveAvailable: Bool = false,
        copies: [DestinationKind: CopyStatus], dropoutCount: Int = 0, mixerDown: Bool = false, now: Date = .now
    ) -> WatchStatus {
        make(isArmed: isArmed, take: take, chips: chips, driveAvailable: driveAvailable,
             copies: TakeCopies(isRunning: !copies.isEmpty) { copies[$0].map(CopyState.init) ?? .recording },
             dropoutCount: dropoutCount, mixerDown: mixerDown, now: now)
    }
}

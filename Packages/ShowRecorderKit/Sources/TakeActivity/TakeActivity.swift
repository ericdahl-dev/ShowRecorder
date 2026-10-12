import Foundation

/// What the Live Activity shows for the running Take (#136). The elapsed time counts on its own from
/// `startedAt`, so the activity only changes when a Marker is added.
public struct TakeActivityContent: Codable, Hashable, Sendable {
    public var showName: String
    public var takeTitle: String
    public var startedAt: Date
    /// The operator's Markers in this Take.
    public var markerCount: Int

    public init(showName: String, takeTitle: String, startedAt: Date, markerCount: Int) {
        self.showName = showName
        self.takeTitle = takeTitle
        self.startedAt = startedAt
        self.markerCount = markerCount
    }

    /// The same Take: only its Marker count may differ.
    func isSameTake(as other: TakeActivityContent) -> Bool {
        showName == other.showName && takeTitle == other.takeTitle && startedAt == other.startedAt
    }
}

/// What to do with the Live Activity.
public enum TakeActivityAction: Equatable, Sendable {
    case none
    case start(TakeActivityContent)
    case update(TakeActivityContent)
    /// A different Take is running than the one shown: end the old activity and start one for this Take.
    case replace(TakeActivityContent)
    case end
}

/// Follows the running Take and says when its Live Activity starts, updates and ends. The app asks it
/// whenever its state may have changed; asking again with nothing new asks for nothing.
public struct TakeActivityTracker: Sendable {
    private var shown: TakeActivityContent?

    public init() {}

    /// `take` is the running Take, or nil when none is running.
    public mutating func next(_ take: TakeActivityContent?) -> TakeActivityAction {
        defer { shown = take }
        switch (shown, take) {
        case (nil, nil): return .none
        case (nil, let take?): return .start(take)
        case (_?, nil): return .end
        case (let shown?, let take?):
            if shown == take { return .none }
            return shown.isSameTake(as: take) ? .update(take) : .replace(take)
        }
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// The Live Activity's type, shared by the app and its widget extension. Everything it shows is in the
/// content state, so the attributes carry nothing.
public struct TakeActivityAttributes: ActivityAttributes {
    public typealias ContentState = TakeActivityContent

    public init() {}
}
#endif

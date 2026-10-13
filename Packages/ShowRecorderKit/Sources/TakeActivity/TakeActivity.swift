import Foundation

/// Something that needs attention during the Take, as the Live Activity shows it (#545): the same set the Apple
/// Watch remote shows (iPhone or Drive low on space, a Copy stopped, a Gap or Dropout, Mixer Link lost).
public struct TakeActivityProblem: Codable, Hashable, Sendable {
    /// Stable across updates, so the same problem is recognized.
    public var id: String
    public var text: String
    /// An SF Symbol name.
    public var symbol: String

    public init(id: String, text: String, symbol: String) {
        self.id = id
        self.text = text
        self.symbol = symbol
    }
}

/// What the Live Activity shows for the running Take (#136). The elapsed time counts on its own from
/// `startedAt`, so the activity only changes when a Marker is added or a problem comes or goes.
public struct TakeActivityContent: Codable, Hashable, Sendable {
    public var showName: String
    public var takeTitle: String
    public var startedAt: Date
    /// The operator's Markers in this Take.
    public var markerCount: Int
    /// What needs attention now, most important first (#545).
    public var problems: [TakeActivityProblem]

    public init(showName: String, takeTitle: String, startedAt: Date, markerCount: Int, problems: [TakeActivityProblem] = []) {
        self.showName = showName
        self.takeTitle = takeTitle
        self.startedAt = startedAt
        self.markerCount = markerCount
        self.problems = problems
    }

    private enum CodingKeys: String, CodingKey { case showName, takeTitle, startedAt, markerCount, problems }

    /// Content from a build before problems existed reads with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showName = try container.decode(String.self, forKey: .showName)
        takeTitle = try container.decode(String.self, forKey: .takeTitle)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        markerCount = try container.decode(Int.self, forKey: .markerCount)
        problems = try container.decodeIfPresent([TakeActivityProblem].self, forKey: .problems) ?? []
    }

    /// The same Take: only its Marker count may differ.
    func isSameTake(as other: TakeActivityContent) -> Bool {
        showName == other.showName && takeTitle == other.takeTitle && startedAt == other.startedAt
    }
}

/// An alert to send with a Live Activity update: it lights up the iPhone and buzzes the Apple Watch, even with
/// neither app open (#545).
public struct TakeActivityAlert: Equatable, Sendable {
    public var title: String
    public var body: String
}

/// Decides when a problem during a Take alerts (#545): once when it first appears, never on an ordinary update, and
/// not again when it clears and comes back within a few minutes (a flapping Mixer Link buzzes once). Problems that
/// appear together are one alert. Recovery updates the activity without an alert.
public struct ProblemAlertGate: Sendable {
    /// How long after its last alert a problem that clears and comes back alerts again.
    public static let repeatAfter: TimeInterval = 300
    private var showing: Set<String> = []
    private var alertedAt: [String: Date] = [:]

    public init() {}

    /// A new Take: everything may alert again. Problems already there as it starts were seen as Record was pressed,
    /// so they don't alert now; if one clears and comes back, it does.
    public mutating func takeStarted(with problems: [TakeActivityProblem]) {
        showing = Set(problems.map(\.id))
        alertedAt = [:]
    }

    /// `problems` is what needs attention now; nil when nothing new should alert.
    public mutating func alert(for problems: [TakeActivityProblem], at now: Date) -> TakeActivityAlert? {
        defer { showing = Set(problems.map(\.id)) }
        let new = problems.filter { problem in
            guard !showing.contains(problem.id) else { return false }
            guard let last = alertedAt[problem.id] else { return true }
            return now.timeIntervalSince(last) > Self.repeatAfter
        }
        guard let first = new.first else { return nil }
        for problem in new { alertedAt[problem.id] = now }
        let others = new.dropFirst().map(\.text)
        let body = others.isEmpty ? "The Take carries on." : "Also: \(others.joined(separator: ", ")). The Take carries on."
        return TakeActivityAlert(title: first.text, body: body)
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

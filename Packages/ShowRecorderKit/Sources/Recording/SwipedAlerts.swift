import Foundation

/// Warnings and green summaries the operator swiped off the record screen (#644, #698). Green good news also fades
/// by itself, which counts as a swipe (#758).
public struct SwipedAlerts: Equatable, Sendable {
    /// How long a green good-news banner shows before it fades (#758).
    public static let fadeAfter: TimeInterval = 10

    /// The swipe key (or text) each swiped alert had, by id.
    private var swiped: [String: String] = [:]
    /// When the green alert on top, with this swipe key (or text), came to the top, by id.
    private var firstSeen: [String: Seen] = [:]

    private struct Seen: Equatable, Sendable {
        var key: String
        var at: Date
    }

    public init() {}

    /// Which alerts can be swiped: a warning (#644) and a green summary such as the Copy summary after a Take (#698).
    /// A critical alert stays until its problem is gone; a hint has its own way to go.
    public static func isSwipeable(_ alert: ScreenAlert) -> Bool { alert.tone == .warning || alert.tone == .ok }

    public mutating func swipe(_ alert: ScreenAlert) {
        guard Self.isSwipeable(alert) else { return }
        swiped[alert.id] = alert.swipeKey ?? alert.text
    }

    /// The alerts still to show. One whose text (or swipe key) has changed since the swipe, or that has turned critical, shows again.
    public func showing(_ alerts: [ScreenAlert]) -> [ScreenAlert] {
        alerts.filter { !Self.isSwipeable($0) || swiped[$0.id] != ($0.swipeKey ?? $0.text) }
    }

    /// Swipes the green good-news alert (`.ok`) on top once it has been on top for `fadeAfter` (#758).
    /// Returns when it fades, or nil. Warnings, critical alerts and blue hints never fade.
    public mutating func fade(_ alerts: [ScreenAlert], at now: Date) -> Date? {
        // Only the alert on top is on screen; one behind it is a "+1 more", so its 10 s haven't started.
        guard let alert = AlertQueue(showing(alerts)).top, alert.tone == .ok else {
            firstSeen = [:]
            return nil
        }
        let key = alert.swipeKey ?? alert.text
        // A clock set back never pushes the fade past 10 s from now.
        let since = min(firstSeen[alert.id].flatMap { $0.key == key ? $0.at : nil } ?? now, now)
        let due = since.addingTimeInterval(Self.fadeAfter)
        guard now < due else {
            swipe(alert)
            firstSeen = [:]
            return nil
        }
        firstSeen = [alert.id: Seen(key: key, at: since)]
        return due
    }

    /// Forgets the swipes of alerts no longer raised, so one that comes back shows again.
    public mutating func forget(absentFrom alerts: [ScreenAlert]) {
        let ids = Set(alerts.map(\.id))
        swiped = swiped.filter { ids.contains($0.key) }
    }
}

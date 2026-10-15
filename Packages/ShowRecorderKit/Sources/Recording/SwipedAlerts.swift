/// Warnings and green summaries the operator swiped off the record screen (#644, #698).
public struct SwipedAlerts: Equatable, Sendable {
    /// The swipe key (or text) each swiped alert had, by id.
    private var swiped: [String: String] = [:]

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

    /// Forgets the swipes of alerts no longer raised, so one that comes back shows again.
    public mutating func forget(absentFrom alerts: [ScreenAlert]) {
        let ids = Set(alerts.map(\.id))
        swiped = swiped.filter { ids.contains($0.key) }
    }
}

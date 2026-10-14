/// Warnings the operator swiped off the record screen (#644).
public struct SwipedAlerts: Equatable, Sendable {
    /// The swipe key (or text) each swiped alert had, by id.
    private var swiped: [String: String] = [:]

    public init() {}

    /// Only a warning goes; a critical alert stays until its problem is gone.
    public mutating func swipe(_ alert: ScreenAlert) {
        guard alert.tone == .warning else { return }
        swiped[alert.id] = alert.swipeKey ?? alert.text
    }

    /// The alerts still to show. One whose text (or swipe key) has changed since the swipe, or that has turned critical, shows again.
    public func showing(_ alerts: [ScreenAlert]) -> [ScreenAlert] {
        alerts.filter { $0.tone != .warning || swiped[$0.id] != ($0.swipeKey ?? $0.text) }
    }

    /// Forgets the swipes of alerts no longer raised, so one that comes back shows again.
    public mutating func forget(absentFrom alerts: [ScreenAlert]) {
        let ids = Set(alerts.map(\.id))
        swiped = swiped.filter { ids.contains($0.key) }
    }
}

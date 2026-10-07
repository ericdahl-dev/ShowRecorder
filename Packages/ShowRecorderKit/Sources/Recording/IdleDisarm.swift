import Foundation

/// When an Armed recorder that nobody is using should stop listening: 30 minutes after the screen
/// locked (or the app left the front) with no Take running. The app tells it when the screen goes idle
/// and comes back, and asks it regularly whether to disarm. It never says to disarm during a Take; a Take
/// counts as use, so the 30 minutes start again when it ends.
///
/// The clock is passed in, so tests don't wait.
public struct IdleDisarm: Sendable, Equatable {
    /// How long a locked, unused recorder stays Armed.
    public static let limit: TimeInterval = 30 * 60

    private var idleSince: Date?

    public init() {}

    /// The screen locked, or the app went to the background. A second call keeps the first time.
    public mutating func becameIdle(at date: Date) {
        if idleSince == nil { idleSince = date }
    }

    /// The app is in front again.
    public mutating func becameActive() {
        idleSince = nil
    }

    /// Whether to disarm now.
    public mutating func shouldDisarm(at date: Date, isRecording: Bool) -> Bool {
        guard let since = idleSince else { return false }
        if isRecording {
            idleSince = date
            return false
        }
        return date.timeIntervalSince(since) >= Self.limit
    }
}

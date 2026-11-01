import Foundation

/// When a Ready recorder that nobody is using should stop listening: 30 minutes after the screen
/// locked (or the app left the front) with no Take running. The app tells it when the screen goes idle
/// and comes back, and asks it regularly whether to stand down. It never says to stand down during a Take; a Take
/// counts as use, so the 30 minutes start again when it ends.
///
/// The clock is passed in, so tests don't wait.
public struct IdleStandDown: Sendable, Equatable {
    /// How long a locked, unused recorder stays Ready.
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

    /// Whether to stand down now.
    public mutating func shouldStandDown(at date: Date, isRecording: Bool) -> Bool {
        guard let since = idleSince else { return false }
        if isRecording {
            idleSince = date
            return false
        }
        return date.timeIntervalSince(since) >= Self.limit
    }
}

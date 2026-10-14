import Foundation

/// Keeps the landscape banner up for a moment once shown, so a problem that flickers doesn't flicker the row
/// between the banner and the chips (#644).
public struct AlertHold: Equatable, Sendable {
    /// How long an alert stays once shown, in seconds.
    public static let minimum: TimeInterval = 2

    private var held: ScreenAlert?
    /// When `held` first showed.
    private var since = Date.distantPast

    public init() {}

    /// What to show now, given the most urgent alert raised.
    public mutating func update(_ current: ScreenAlert?, at now: Date) -> ScreenAlert? {
        if let current {
            if current.id != held?.id { since = now }
            held = current
        } else if now.timeIntervalSince(since) >= Self.minimum {
            held = nil
        }
        return held
    }

    /// Lets the shown alert go now: the operator swiped it away.
    public mutating func release() {
        held = nil
    }
}

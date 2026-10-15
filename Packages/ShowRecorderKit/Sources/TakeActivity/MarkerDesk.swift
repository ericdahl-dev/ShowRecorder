import Foundation

/// Where the Live Activity's Marker button (#684) reaches the running Take. The button's App Intent runs in the app's own
/// process; the record screen's model wires `place` to the same path as the Marker button, the watch and the Take menu,
/// so the Free limit (#705) and "a Take must be running" are judged there, once.
@MainActor
public final class MarkerDesk {
    public static let shared = MarkerDesk()

    /// How long after a Marker one more tap counts as the same tap (a Live Activity button can deliver a tap twice).
    nonisolated public static let window: TimeInterval = 0.5

    /// Places a Marker; returns whether it did. Nil until the app has wired it.
    public var place: (@MainActor () -> Bool)?
    private var lastPlacedAt: Date?

    public init() {}

    /// A tap on the button. Returns whether a Marker was placed: not with nothing wired, not for a repeat of the
    /// last tap, and not when the app refuses (no Take, past the limit); a refused tap doesn't start the window.
    @discardableResult
    public func tap(at now: Date = .now) -> Bool {
        // A clock that stepped back is outside the window: it must not swallow taps until it catches up.
        if let lastPlacedAt, (0..<Self.window).contains(now.timeIntervalSince(lastPlacedAt)) { return false }
        guard let place, place() else { return false }
        lastPlacedAt = now
        return true
    }
}

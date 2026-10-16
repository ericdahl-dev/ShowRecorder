import Foundation

/// The decisions behind the iPhone's hold-to-stop button (#753), apart from SwiftUI so they can be tested: the ring fills
/// while a press lasts, a finished hold stops the Take, and an early release asks for the "Hold to stop" hint.
public struct HoldToStopGesture: Sendable {
    public static let holdSeconds = 1.0

    public enum Outcome: Equatable, Sendable {
        case nothing, showHint
    }

    /// Whether the red ring is filling.
    public private(set) var isFilling = false
    private var pressedAt = Date.distantPast
    private var completed = false

    public init() {}

    public mutating func pressBegan(at now: Date) {
        completed = false
        pressedAt = now
        isFilling = true
    }

    /// The hold lasted the full second; the caller stops the Take.
    public mutating func holdCompleted() {
        completed = true
        isFilling = false
    }

    /// A release before the hold finished is a tap. It is judged by time as well as by `completed`, so a finished hold
    /// never shows the hint whichever of SwiftUI's two callbacks comes first.
    public mutating func pressEnded(at now: Date) -> Outcome {
        isFilling = false
        guard !completed, now.timeIntervalSince(pressedAt) < Self.holdSeconds * 0.9 else { return .nothing }
        return .showHint
    }
}

/// The "Hold to stop" hint after a tap: up for `seconds`, and an earlier tap's timer never clears a newer hint.
public struct StopHint: Sendable {
    public static let seconds = 2.0
    public private(set) var isShown = false
    private var generation = 0

    public init() {}

    /// Shows the hint and returns the token its timer passes to `expire`.
    public mutating func show() -> Int {
        generation += 1
        isShown = true
        return generation
    }

    public mutating func expire(_ token: Int) {
        if token == generation { isShown = false }
    }

    public mutating func clear() {
        generation += 1
        isShown = false
    }
}

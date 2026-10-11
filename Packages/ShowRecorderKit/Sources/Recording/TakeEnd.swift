/// Which Take ended and why, so the screen can say so. A new value for every Take, even when the reason repeats.
public struct TakeEnd: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// Record was stopped: by the operator, a Mixer Trigger, or the app.
        case stopped
        /// The recorder ended it because the last healthy Destination was about to fill.
        case outOfSpace
        /// The recorder ended it because no Destination could be written any more.
        case noDestination

        /// What to tell the operator, or nil when nothing needs saying.
        public var message: String? {
            switch self {
            case .stopped: nil
            case .outOfSpace: "Recording stopped because the last Destination was about to fill. Everything recorded was saved."
            case .noDestination: "Recording stopped because no Destination could be written. Everything recorded so far was saved."
            }
        }
    }

    public var take: Int
    public var reason: Reason

    public init(take: Int, reason: Reason) {
        self.take = take
        self.reason = reason
    }
}

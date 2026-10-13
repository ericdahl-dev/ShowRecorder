/// Which Take ended and why, so the screen can say so. A new value for every Take, even when the reason repeats.
public struct TakeEnd: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// Record was stopped: by the operator, a Mixer Trigger, or the app.
        case stopped
        /// The recorder ended it because the last healthy Destination was about to fill.
        case outOfSpace
        /// The recorder ended it because no Destination could be written any more.
        case noDestination
        /// The input moved to a device with a different USB Channel count or sample rate, so the Take couldn't
        /// go on into the same Stems (#301).
        case inputChanged

        /// What to tell the operator, or nil when nothing needs saying.
        public var message: String? {
            switch self {
            case .stopped: nil
            case .outOfSpace: "Recording stopped because the last Destination was about to fill. Everything recorded was saved."
            case .noDestination: "Recording stopped because no Destination could be written. Everything recorded so far was saved."
            case .inputChanged: "The audio input changed format during the Take. Recording stopped and the Stems recorded so far were saved. Press record to start a new Take."
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

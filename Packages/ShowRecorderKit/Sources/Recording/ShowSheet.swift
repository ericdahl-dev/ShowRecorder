import Foundation

/// What the Show sheet offers, reached by tapping the Show line on the record screen: End Show
/// first when a Show is open, then a way to start another. Both wait for the Take to stop.
public struct ShowSheet: Sendable, Equatable {
    public let openShowName: String?
    public let isRecording: Bool

    public init(openShowName: String?, isRecording: Bool) {
        self.openShowName = openShowName
        self.isRecording = isRecording
    }

    public var title: String { "Show" }

    public var offersEndShow: Bool { openShowName != nil }
    /// End Show is the first thing in the sheet whenever there is a Show to end.
    public var endShowFirst: Bool { offersEndShow }
    public var canEndShow: Bool { offersEndShow && !isRecording }
    public var canStartShow: Bool { !isRecording }

    public var endShowNote: String {
        isRecording
            ? "A Show can't be ended during a Take."
            : "Ending a Show keeps its files. The next record starts a new Show. A Show also ends after 6 hours with no Take."
    }

    public var startShowNote: String {
        isRecording
            ? "A Show can't be started during a Take."
            : "Starting a Show ends the open one. The next Take is Take 01 of the new Show. Leave the name blank for \"Show\"."
    }
}

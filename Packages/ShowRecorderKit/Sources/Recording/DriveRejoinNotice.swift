/// Tells the operator the Drive is back after it stopped mid-Take. Feed it the Drive's status as it changes.
public struct DriveRejoinNotice: Equatable, Sendable {
    private var wasInterrupted = false
    private var showing = false

    public init() {}

    public mutating func update(isRecording: Bool, drive: CopyStatus) {
        guard isRecording else {
            wasInterrupted = false
            showing = false
            return
        }
        if drive == .interrupted {
            wasInterrupted = true
            showing = false
        } else if wasInterrupted, drive == .recording {
            wasInterrupted = false
            showing = true
        }
    }

    public var alert: ScreenAlert? {
        showing ? ScreenAlert(id: "drive-back", priority: .destination, tone: .ok, text: "The Drive is back. The Gap will be Repaired after the Take.") : nil
    }
}

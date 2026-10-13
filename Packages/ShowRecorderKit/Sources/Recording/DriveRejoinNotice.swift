/// Tells the operator the Drive is back after it stopped mid-Take. Feed it the Take's Copies as they change.
public struct DriveRejoinNotice: Equatable, Sendable {
    private var wasInterrupted = false
    private var showing = false

    public init() {}

    public mutating func update(copies: TakeCopies) {
        let drive = copies[.drive]
        guard copies.isRunning else {
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

    /// Today's call with the Drive's running word, until the record screen reads `TakeCopies` itself (#550).
    public mutating func update(isRecording: Bool, drive: CopyStatus) {
        update(copies: TakeCopies(isRunning: isRecording) { $0 == .drive ? CopyState(drive) : .recording })
    }

    public var alert: ScreenAlert? {
        showing ? ScreenAlert(id: "drive-back", priority: .destination, tone: .ok, text: "The Drive is back. The Gap will be Repaired after the Take.") : nil
    }
}

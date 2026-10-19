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
        // A Drive that was full (#560) and has room again rejoins like one that stopped: it left a Gap too.
        if drive == .interrupted || drive == .full {
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

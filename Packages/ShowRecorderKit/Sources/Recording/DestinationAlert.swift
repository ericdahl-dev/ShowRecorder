/// What the record screen says about the Copies of a running Take. A Copy that stops mid-Take is critical and
/// has its own id; having no Drive from the start is a quiet warning.
public enum DestinationAlert {
    /// - Parameter checkedAndNotFound: the operator tapped Check Drive and the Drive was still not there.
    /// - Parameter deviceWord: what a Drive only Take calls the device the app runs on: iPhone, iPad or Mac.
    public static func make(copies: TakeCopies, checkedAndNotFound: Bool = false, deviceWord: String = "iPhone") -> ScreenAlert? {
        guard copies.isRunning else { return nil }
        switch (copies[.device], copies[.drive]) {
        case (.interrupted, .interrupted):
            return ScreenAlert(id: "both-stopped", priority: .destination, tone: .critical, text: "Both Copies stopped writing.")
        case (.interrupted, _):
            return ScreenAlert(
                id: "device-stopped", priority: .destination, tone: .critical,
                text: "The Device stopped writing. Recording continues on the Drive.")
        case (_, .interrupted):
            return ScreenAlert(
                id: "drive-stopped", priority: .destination, tone: .critical,
                text: (checkedAndNotFound ? "Still not found. " : "")
                    + (copies.isDriveOnly
                        ? "The Drive stopped. Recording to this \(deviceWord) until it's back; the audio moves to the Drive after the Take."
                        : "The Drive stopped. Recording continues on the Device; the Gap is Repaired when the Drive comes back."),
                action: .checkDrive)
        case (_, .missing):
            return ScreenAlert(
                id: "no-drive", priority: .destination, tone: .warning,
                text: copies.isDriveOnly
                    ? "No Drive: recording to this \(deviceWord); it moves to the Drive when one is connected."
                    : "No Drive. Recording to the Device only.")
        default:
            return nil
        }
    }

    /// Today's call with the two running words, until the record screen reads `TakeCopies` itself (#550).
    public static func make(isRecording: Bool, device: CopyStatus, drive: CopyStatus, checkedAndNotFound: Bool = false) -> ScreenAlert? {
        make(copies: TakeCopies(isRunning: isRecording) { CopyState($0 == .device ? device : drive) },
             checkedAndNotFound: checkedAndNotFound)
    }
}

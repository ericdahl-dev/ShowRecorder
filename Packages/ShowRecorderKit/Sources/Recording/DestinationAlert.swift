/// What the record screen says about the Copies of a running Take. A Copy that stops mid-Take is critical and
/// has its own id; having no Drive from the start is a quiet warning.
public enum DestinationAlert {
    /// - Parameter checkedAndNotFound: the operator tapped Check Drive and the Drive was still not there.
    /// - Parameter deviceWord: what a Drive only Take calls the device the app runs on: iPhone, iPad or Mac.
    /// - Parameter driveNote: why the Take started without its Drive, when the press found none (#814).
    /// - Parameter driveCopyAllowed: false on Free, which has no Drive Copy: then having none is no warning.
    public static func make(
        copies: TakeCopies, checkedAndNotFound: Bool = false, deviceWord: String = "iPhone", driveNote: String? = nil,
        driveCopyAllowed: Bool = true
    ) -> ScreenAlert? {
        guard copies.isRunning else { return nil }
        switch (copies[.device], copies[.drive]) {
        case (.interrupted, .interrupted):
            return ScreenAlert(id: "both-stopped", priority: .destination, tone: .critical, text: "Both Copies stopped writing.")
        case (.interrupted, _):
            return ScreenAlert(
                id: "device-stopped", priority: .destination, tone: .critical,
                text: "The Device stopped writing. Recording continues on the Drive.")
        case (.standingIn, _) where copies.isDriveOnly:
            return ScreenAlert(
                id: "drive-stopped", priority: .destination, tone: .critical,
                text: "The Drive stopped. Recording to this \(deviceWord) for the rest of the Take; the audio moves to the Drive after it.")
        case (_, .interrupted):
            return ScreenAlert(
                id: "drive-stopped", priority: .destination, tone: .critical,
                text: (checkedAndNotFound ? "Still not found. " : "")
                    + "The Drive stopped. Recording continues on the Device; the Gap is Repaired when the Drive comes back.",
                action: .checkDrive)
        case (_, .missing):
            guard driveCopyAllowed else { return nil }
            return ScreenAlert(
                id: "no-drive", priority: .destination, tone: .warning,
                text: (copies.isDriveOnly
                    ? "No Drive: recording to this \(deviceWord); it moves to the Drive when one is connected."
                    : "No Drive. Recording to the Device only.") + (driveNote.map { " \($0)" } ?? ""))
        default:
            return nil
        }
    }
}

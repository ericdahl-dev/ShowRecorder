/// What the record screen says about the Copies of a running Take. A Copy that stops mid-Take is critical and
/// has its own id; having no Drive from the start is a quiet warning.
public enum DestinationAlert {
    /// - Parameter checkedAndNotFound: the operator tapped Check Drive and the Drive was still not there.
    public static func make(isRecording: Bool, device: CopyStatus, drive: CopyStatus, checkedAndNotFound: Bool = false) -> ScreenAlert? {
        guard isRecording else { return nil }
        switch (device, drive) {
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
                    + "The Drive stopped. Recording continues on the Device; the Gap is Repaired when the Drive comes back.",
                action: .checkDrive)
        case (_, .missing):
            return ScreenAlert(id: "no-drive", priority: .destination, tone: .warning, text: "No Drive. Recording to the Device only.")
        default:
            return nil
        }
    }
}

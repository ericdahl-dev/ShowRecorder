/// What the record screen says about the Copies of a running Take. A Copy that stops or fills mid-Take is critical and
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
        let device = copies[.device], drive = copies[.drive]
        func stopped(_ state: CopyState) -> Bool { state == .interrupted || state == .full }
        switch (device, drive) {
        case _ where stopped(device) && stopped(drive):
            // Full is told apart from failed (#560); two Copies of different kinds are just stopped.
            return ScreenAlert(
                id: "both-stopped", priority: .destination, tone: .critical,
                text: device == .full && drive == .full ? "Both Copies are full." : "Both Copies stopped writing.")
        case (.full, _):
            return ScreenAlert(
                id: "device-full", priority: .destination, tone: .critical,
                text: "This \(deviceWord) is full. Recording continues on the Drive.")
        case (.interrupted, _):
            return ScreenAlert(
                id: "device-stopped", priority: .destination, tone: .critical,
                text: "The Device stopped writing. Recording continues on the Drive.")
        case (.standingIn, .full) where copies.isDriveOnly:
            return ScreenAlert(
                id: "drive-full", priority: .destination, tone: .critical,
                text: "The Drive is full. Recording to this \(deviceWord) for the rest of the Take; the audio moves to the Drive after it.")
        case (.standingIn, _) where copies.isDriveOnly:
            return ScreenAlert(
                id: "drive-stopped", priority: .destination, tone: .critical,
                text: "The Drive stopped. Recording to this \(deviceWord) for the rest of the Take; the audio moves to the Drive after it.")
        case (_, .full):
            // No Repair promised: a full Drive's Gap isn't filled until someone frees space.
            return ScreenAlert(
                id: "drive-full", priority: .destination, tone: .critical,
                text: "The Drive is full. Recording continues on the Device.")
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

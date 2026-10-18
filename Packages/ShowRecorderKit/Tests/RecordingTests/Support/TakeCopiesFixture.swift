@testable import Recording

/// A running (or ended) Take's Copies, for the screens' tests (#550).
func takeCopies(running: Bool = true, driveOnly: Bool = false, deviceOnly: Bool = false, device: CopyState, drive: CopyState) -> TakeCopies {
    TakeCopies(isRunning: running, isDriveOnly: driveOnly, isDeviceOnly: deviceOnly) { $0 == .device ? device : drive }
}

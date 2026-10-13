@testable import Recording

/// A running (or ended) Take's Copies, for the screens' tests (#550).
func takeCopies(running: Bool = true, device: CopyState, drive: CopyState) -> TakeCopies {
    TakeCopies(isRunning: running) { $0 == .device ? device : drive }
}

import SwiftUI

/// Asks iOS for time to finish saving a Take when the app goes to the background mid-save (#818): a few more seconds
/// before it is suspended, enough for most saves. A longer one is suspended all the same; the Stop's progress watch then
/// treats the suspended time as no stall (see `ProgressWatch`), and an abandoned Copy is finished at the next launch.
/// Counted: the task lasts while anything holds it, so a second Stop can't end the first one's. Nothing to do on the Mac.
@MainActor
final class SaveBackgroundTask {
    private var holds = 0
    /// Whether the screen's own look at `Recorder.isFinishing` is one of the holds.
    private var following = false

    func hold() {
        holds += 1
        if holds == 1 { begin() }
    }

    func release() {
        guard holds > 0 else { return }
        holds -= 1
        if holds == 0 { end() }
    }

    /// Holds while the recorder is saving a Take, whoever ended it (the Stop button, the watch, the recorder itself).
    func follow(isFinishing: Bool) {
        guard isFinishing != following else { return }
        following = isFinishing
        if isFinishing { hold() } else { release() }
    }

    #if os(iOS)
    private var identifier = UIBackgroundTaskIdentifier.invalid

    private func begin() {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "ShowRecorder save") { [weak self] in
            // The time is up and iOS suspends the app next: the task is handed back before this returns. UIKit calls it on
            // the main thread.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    private func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
    #else
    private func begin() {}
    private func end() {}
    #endif
}

#if os(macOS)
import AppKit
import Recording

/// Command-Q (or Quit from the Dock) during a Take asks "Stop the Take?" first, as closing the window does.
/// Keep Recording cancels the quit; Stop Recording ends the Take and quits (see `RecorderLifecycle.quitRequested`).
final class QuitGuard: NSObject, NSApplicationDelegate {
    /// Set by the app once its model exists.
    @MainActor static weak var model: RecordScreenModel?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, RecorderLifecycle.quitRequested(isRecording: model.recorder.isRecording) == .askToStop else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Stop the Take?"
        alert.informativeText = "\(model.takeTitle) is still recording. Quitting ends it."
        alert.addButton(withTitle: "Keep Recording")
        alert.addButton(withTitle: "Stop Recording").hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        model.stop()
        return .terminateNow
    }
}
#endif

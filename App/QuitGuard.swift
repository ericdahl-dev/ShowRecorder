#if os(macOS)
import AppKit
import Recording

/// Command-Q (or Quit from the Dock) during a Take asks "Stop the Take?" first, as closing the window does.
/// Keep Going cancels the quit; Stop Take ends the Take and quits (see `TakeSequencer.quitRequested`).
final class QuitGuard: NSObject, NSApplicationDelegate {
    /// Set by the app once its model exists.
    @MainActor static weak var model: RecordScreenModel?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, model.sequencer.quitRequested() == .askToStop else {
            return .terminateNow
        }
        // Stop was already pressed: nothing left to decide, so the app waits for the Stems to be written.
        if !model.recorder.isRecording {
            Task {
                await model.stop()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        let alert = NSAlert()
        alert.messageText = "Stop the Take?"
        alert.informativeText = "\(model.takeTitle) is still recording. Quitting ends it."
        alert.addButton(withTitle: "Keep Going")
        alert.addButton(withTitle: "Stop Take").hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        // Quit waits for the Take to finish (Stems written), then replies.
        Task {
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif

#if os(macOS)
import AppKit
import Recording
import SwiftUI

/// Closing the record window during a Take asks "Stop the Take?" first. Keep Recording leaves the window
/// and the Take alone; Stop Recording ends the Take and closes the window. With no Take running the window
/// closes as usual (see `RecorderLifecycle.windowCloseRequested`).
///
/// It sits behind the window as an invisible view and puts itself in as the window's delegate, forwarding
/// everything but `windowShouldClose` to the delegate SwiftUI installed, so the window otherwise behaves
/// as before. Both the close button and Command-W go through `windowShouldClose`.
struct WindowCloseGuard: NSViewRepresentable {
    let model: RecordScreenModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in context.coordinator.install(on: view?.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in context.coordinator.install(on: view?.window) }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private let model: RecordScreenModel
        /// SwiftUI's own delegate for the window. Only read to forward calls to it.
        nonisolated(unsafe) private weak var original: (any NSWindowDelegate)?

        init(model: RecordScreenModel) {
            self.model = model
        }

        func install(on window: NSWindow?) {
            guard let window, window.delegate !== self else { return }
            original = window.delegate
            window.delegate = self
        }

        nonisolated override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (original as? NSObject)?.responds(to: aSelector) == true
        }

        nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
            (original as? NSObject)?.responds(to: aSelector) == true ? original : super.forwardingTarget(for: aSelector)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            switch RecorderLifecycle.windowCloseRequested(isRecording: model.recorder.isRecording) {
            case .close:
                return original?.windowShouldClose?(sender) ?? true
            case .askToStop:
                ask(in: sender)
                return false
            }
        }

        private func ask(in window: NSWindow) {
            let alert = NSAlert()
            alert.messageText = "Stop the Take?"
            alert.informativeText = "\(model.takeTitle) is still recording. Closing the window ends it."
            alert.addButton(withTitle: "Keep Recording")
            alert.addButton(withTitle: "Stop Recording").hasDestructiveAction = true
            alert.beginSheetModal(for: window) { [weak self, weak window] response in
                guard response == .alertSecondButtonReturn else { return }
                self?.model.stop()
                window?.close()
            }
        }
    }
}
#endif

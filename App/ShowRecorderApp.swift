import SwiftUI

@main
struct ShowRecorderApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(QuitGuard.self) private var quitGuard
    #endif
    /// Owned here so the record screen and the Mac Settings scene share one model.
    @State private var model = RecordScreenModel()

    var body: some Scene {
        windowScene
            .commands { takeCommands }
        #if os(macOS)
        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 520)
                .modifier(AppearanceRoot(mode: model.appearance))
        }
        #endif
    }

    /// The Take menu: the one place for the shortcuts (Mac menu bar, and the iPad shortcut list). Stop asks first,
    /// like the Stop button. Marker is Shift-Command-M because Command-M is Minimize on the Mac.
    @CommandsBuilder private var takeCommands: some Commands {
        #if os(macOS)
        CommandGroup(replacing: .newItem) {}
        #endif
        CommandMenu("Take") {
            Button("Record") { model.record() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.recorder.isArmed || model.recorder.isRecording)
            Button("Stop Take…") { model.confirmingStop = true }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.recorder.isRecording)
            Button("Add Marker") { model.sequencer.addMarker() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!model.recorder.isRecording)
        }
    }

    private var windowScene: some Scene {
        #if os(macOS)
        // One window: a second one would share this model, and closing it would disarm the recorder, so File >
        // New Window is removed (see `takeCommands`).
        WindowGroup {
            RecordScreen(model: model)
                .modifier(AppearanceRoot(mode: model.appearance))
                .onAppear {
                    QuitGuard.model = model
                    // `-screenshotWindow` (Debug only): a 1280 x 800 window, title bar included, which captures at
                    // 2560 x 1600 on a Retina display, one of the Mac App Store's 16:10 sizes (2880 x 1800 needs a taller screen).
                    if launchFlag("-screenshotWindow") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            for window in NSApplication.shared.windows where window.isVisible && window.title == "ShowRecorder" {
                                // On a Retina screen when there is one, so it captures at 2x.
                                let screen = NSScreen.screens.first { $0.backingScaleFactor >= 2 } ?? window.screen
                                let origin = screen?.visibleFrame.origin ?? .zero
                                window.setFrame(NSRect(x: origin.x + 20, y: origin.y + 20, width: 1280, height: 800), display: true)
                            }
                        }
                    }
                }
        }
        .defaultSize(width: 1100, height: 720)
        #else
        WindowGroup {
            RecordScreen(model: model)
                .modifier(AppearanceRoot(mode: model.appearance))
        }
        #endif
    }
}

import SwiftUI

@main
struct ShowRecorderApp: App {
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
            Button("Stop Recording…") { model.confirmingStop = true }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.recorder.isRecording)
            Button("Add Marker") { model.recorder.addMarker() }
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

import SwiftUI

@main
struct ShowRecorderApp: App {
    /// Owned here so the record screen and the Mac Settings scene share one model.
    @State private var model = RecordScreenModel()

    var body: some Scene {
        windowScene
        #if os(macOS)
        Settings {
            SettingsView(model: model)
                .frame(width: 520, height: 520)
                .modifier(AppearanceRoot(mode: model.appearance))
        }
        #endif
    }

    private var windowScene: some Scene {
        #if os(macOS)
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

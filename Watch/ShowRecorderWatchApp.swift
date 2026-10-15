import SwiftUI
import WatchKit
import WatchRemote

/// The Apple Watch remote (#100): see what the iPhone recorder is doing, and Start, Stop and add Markers from the
/// wrist. It holds no audio, no Takes and no setup: a view of the recorder plus three commands.
@main
struct ShowRecorderWatchApp: App {
    @State private var model: WatchRemoteModel = DemoLink.isOn ? DemoLink().model : WatchSessionLink().model
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RemoteView(model: model)
        }
        .onChange(of: phase) { _, phase in
            // A raised wrist: the link comes back now the app is in front.
            if phase == .active { model.appBecameActive() }
        }
    }
}

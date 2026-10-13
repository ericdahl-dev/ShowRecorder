import SwiftUI
import WatchKit
import WatchRemote

/// The Apple Watch remote (#100): see what the iPhone recorder is doing, and Start, Stop and add Markers from the
/// wrist. It holds no audio, no Takes and no setup: a view of the recorder plus three commands.
@main
struct ShowRecorderWatchApp: App {
    @State private var link = WatchSessionLink()

    var body: some Scene {
        WindowGroup {
            RemoteView(model: link.model)
                .onAppear { link.start() }
        }
    }
}

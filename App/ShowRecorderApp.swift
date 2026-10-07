import SwiftUI

@main
struct ShowRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            RecordScreen()
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}

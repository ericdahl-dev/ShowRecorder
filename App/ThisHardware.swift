#if os(iOS)
import UIKit
#endif

/// What to call the hardware the app runs on in copy: "this iPhone", "this iPad", "this Mac" (CONTEXT.md avoids
/// "this device").
@MainActor
enum ThisHardware {
    #if os(macOS)
    static let word = "Mac"
    #else
    static let word = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    #endif
}

#if os(iOS)
import AppIntents
import TakeActivity

/// The Live Activity's Marker button (#684). It is a `LiveActivityIntent`, so the system runs `perform()` in the app's
/// own process, not the widget extension's, even with the iPhone locked. The file is in both targets: the extension
/// builds the button from it, the app runs it. It places the Marker through `MarkerDesk`, the same path as the record
/// screen and the Apple Watch.
struct PlaceMarkerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Place Marker"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await MarkerDesk.shared.tap()
        return .result()
    }
}
#endif

import Recording
import SwiftUI

extension Color {
    init(_ rgb: RGB) { self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1) }
}

private struct AppearanceModeKey: EnvironmentKey {
    static let defaultValue = AppearanceMode.system
}

extension EnvironmentValues {
    /// Which appearance the app is in: System, Dark (dark room) or Sunlight (high contrast).
    var appearanceMode: AppearanceMode {
        get { self[AppearanceModeKey.self] }
        set { self[AppearanceModeKey.self] = newValue }
    }
}

extension AppearanceMode {
    var title: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .sunlight: "Sunlight"
        }
    }

    /// Dark forces the dark scheme and Sunlight the light one; System follows the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .sunlight: .light
        }
    }

    var footnote: String {
        switch self {
        case .system: "Follows the device's light or dark setting."
        case .dark: "A dark screen for a dark room."
        case .sunlight: "White background, black text and strong colors, for a bright stage or outdoors."
        }
    }
}

/// Applies the chosen appearance to a whole window: the color scheme, the background and the environment value.
struct AppearanceRoot: ViewModifier {
    let mode: AppearanceMode

    func body(content: Content) -> some View {
        content
            .environment(\.appearanceMode, mode)
            .preferredColorScheme(mode.colorScheme)
            .background {
                if mode != .system { Color(Palette.background(mode)).ignoresSafeArea() }
            }
    }
}

/// Secondary text: the system's gray, or a stronger gray (7:1 or more) in Dark and Sunlight.
struct SecondaryText: ViewModifier {
    @Environment(\.appearanceMode) private var mode

    func body(content: Content) -> some View {
        if mode == .system {
            content.foregroundStyle(.secondary)
        } else {
            content.foregroundStyle(Color(Palette.secondaryText(mode)))
        }
    }
}

extension View {
    func secondaryText() -> some View { modifier(SecondaryText()) }
}

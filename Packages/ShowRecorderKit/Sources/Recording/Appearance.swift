import Foundation

/// How the app looks. Dark is for a dark room; Sunlight is for a bright stage or outdoors: a light, high
/// contrast look. System follows the device and keeps the standard colors.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, dark, sunlight

    private static let key = "appearanceMode"

    public static func load(from defaults: UserDefaults = .standard) -> AppearanceMode {
        defaults.string(forKey: key).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }
}

/// A color in sRGB, 0 to 1.
public struct RGB: Equatable, Sendable {
    public var red: Double, green: Double, blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG contrast ratio with `other`, from 1 to 21.
    public func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The colors of banners and chips, per appearance. Text and fill are chosen together.
public enum Palette {
    public enum Element: CaseIterable, Sendable {
        case alertCritical, alertWarning, alertOk, alertInfo, chipFailed, chipAttention
    }

    public static func pair(for element: Element, mode: AppearanceMode) -> (fill: RGB, text: RGB) {
        let white = RGB(1, 1, 1), black = RGB(0, 0, 0)
        switch (element, mode) {
        case (.alertCritical, .sunlight), (.chipFailed, .sunlight): return (RGB(0.60, 0.05, 0.05), white)
        case (.alertWarning, .sunlight), (.chipAttention, .sunlight): return (RGB(1.0, 0.80, 0.0), black)
        case (.alertOk, .sunlight): return (RGB(0.0, 0.33, 0.14), white)
        case (.alertInfo, .sunlight): return (RGB(0.0, 0.18, 0.50), white)
        case (.alertCritical, _), (.chipFailed, _): return (RGB(0.70, 0.15, 0.12), white)
        case (.alertWarning, _), (.chipAttention, _): return (RGB(1.0, 0.69, 0.13), black)
        case (.alertOk, _): return (RGB(0.12, 0.42, 0.23), white)
        case (.alertInfo, _): return (RGB(0.20, 0.30, 0.55), white)
        }
    }

    /// The screen behind everything, for Dark and Sunlight (System uses the device's).
    public static func background(_ mode: AppearanceMode) -> RGB {
        mode == .sunlight ? RGB(1, 1, 1) : RGB(0.06, 0.06, 0.07)
    }

    public static func primaryText(_ mode: AppearanceMode) -> RGB {
        mode == .sunlight ? RGB(0, 0, 0) : RGB(0.97, 0.97, 0.98)
    }

    /// Secondary text is dimmer, but still 7:1 or better, so labels read in sunlight.
    public static func secondaryText(_ mode: AppearanceMode) -> RGB {
        mode == .sunlight ? RGB(0.24, 0.24, 0.26) : RGB(0.74, 0.75, 0.78)
    }

    /// The colors the level meters draw with.
    public enum MeterColor: CaseIterable, Sendable {
        case green, yellow, red, low, orange
    }

    /// The line drawn around a meter bar in Sunlight, so a bright color still has an edge against white. Nil elsewhere.
    public static func meterOutline(_ mode: AppearanceMode) -> RGB? {
        mode == .sunlight ? RGB(0, 0, 0) : nil
    }

    /// The Marker button's flag: amber in Sunlight, where yellow on a light screen can't be seen.
    public static func markerFlag(_ mode: AppearanceMode) -> RGB {
        mode == .sunlight ? RGB(0.60, 0.45, 0.0) : RGB(1.0, 0.85, 0.20)
    }

    public static func meter(_ color: MeterColor, mode: AppearanceMode) -> RGB {
        if mode == .sunlight {
            switch color {
            case .green: return RGB(0.0, 0.68, 0.24)
            case .yellow: return RGB(1.0, 0.85, 0.0)
            case .red: return RGB(0.73, 0.0, 0.0)
            case .low: return RGB(0.20, 0.35, 0.60)
            case .orange: return RGB(0.80, 0.33, 0.0)
            }
        }
        switch color {
        case .green: return RGB(0.20, 0.85, 0.40)
        case .yellow: return RGB(1.0, 0.85, 0.20)
        case .red: return RGB(1.0, 0.30, 0.28)
        case .low: return RGB(0.45, 0.58, 0.72)
        case .orange: return RGB(1.0, 0.60, 0.15)
        }
    }
}

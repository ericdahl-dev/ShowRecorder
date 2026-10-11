import Foundation

/// The sample rate to record at (#195): the input's own rate ("Interface", nil) or one the input offers. A mixer
/// dictates its rate, so a mixer's USB input offers only that one and is never switched. Above 48 kHz is Pro
/// (ADR 0004): Free, once Pro is offered, records at up to 48 kHz.
public enum SampleRateSetting {
    /// The key it is stored under; 0 stores "Interface".
    public static let key = "sampleRate"

    /// The stored choice, or `platformDefault` when nothing is stored (nil, the interface's rate, on a Mac; 48 kHz
    /// on iPhone and iPad, where the app has always asked for it).
    public static func load(from defaults: UserDefaults = .standard, platformDefault: Int?) -> Int? {
        guard defaults.object(forKey: key) != nil else { return platformDefault }
        let stored = defaults.integer(forKey: key)
        return stored > 0 ? stored : nil
    }

    public static func save(_ rate: Int?, to defaults: UserDefaults = .standard) {
        defaults.set(rate ?? 0, forKey: key)
    }

    /// Whether this tier records at up to 48 kHz only.
    /// An unknown tier (nil, before the App Store has answered) isn't capped (#316).
    public static func capAt48k(proOffered: Bool, tier: Tier?) -> Bool {
        proOffered && tier == .free
    }

    /// The rate to switch the input to before Arming, or nil to leave it as it is.
    public static func rateToSet(chosen: Int?, available: [Int], current: Int, capAt48k: Bool) -> Int? {
        var wanted = chosen ?? current
        if capAt48k, wanted > 48_000 { wanted = 48_000 }
        guard wanted != current, available.contains(wanted) else { return nil }
        return wanted
    }

    /// What the picker offers: "Interface", then each rate the input offers when it offers more than one.
    public static func choices(available: [Int]) -> [Int?] {
        available.count > 1 ? [nil] + available.sorted().map { $0 } : [nil]
    }

    /// "Interface (96 kHz)", "44.1 kHz", "48 kHz".
    public static func label(_ rate: Int?, current: Int?) -> String {
        guard let rate else { return current.map { "Interface (\(kHz($0)))" } ?? "Interface" }
        return kHz(rate)
    }

    private static func kHz(_ rate: Int) -> String {
        String(format: "%g kHz", (Double(rate) / 100).rounded() / 10)
    }
}

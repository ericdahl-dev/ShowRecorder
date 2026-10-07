import Foundation

/// The Pre-roll length setting: how many seconds of audio before the record press a Take starts with.
/// One place to read and write it, so Templates can carry it later.
public enum PreRollSetting {
    /// The lengths Settings offers, in seconds; 0 is Off.
    public static let choices: [Double] = [0, 5, 10, 20]
    public static let defaultSeconds: Double = 10
    /// The key it is stored under.
    public static let key = "preRollSeconds"

    /// The stored length, or the default when nothing valid is stored.
    public static func load(from defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: key) != nil else { return defaultSeconds }
        let stored = defaults.double(forKey: key)
        return choices.contains(stored) ? stored : defaultSeconds
    }

    public static func save(_ seconds: Double, to defaults: UserDefaults = .standard) {
        defaults.set(seconds, forKey: key)
    }

    /// What the Armed recorder holds in memory for `seconds` of Pre-roll: that long plus a second of margin,
    /// as 4-byte samples for every channel. Nothing when off.
    public static func memoryBytes(seconds: Double, channelCount: Int, sampleRate: Double) -> Int {
        guard seconds > 0 else { return 0 }
        return Int((seconds + 1) * sampleRate) * channelCount * MemoryLayout<Float>.size
    }
}

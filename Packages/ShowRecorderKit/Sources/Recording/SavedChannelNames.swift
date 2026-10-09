import Foundation

/// The channel names the operator has typed before, kept on the device so they come back as chips on the
/// channel names page. Newest first, one per name whatever its case. The built-in shortcut names ("Kick",
/// "Vox 2") are not saved: they are chips already.
public enum SavedChannelNames {
    /// How many names are kept.
    public static let limit = 30
    private static let key = "savedChannelNames"

    public static func load(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    /// `names` with `name` added at the front, unless it is a built-in shortcut name.
    static func adding(_ name: String, to names: [String]) -> [String] {
        let lowered = name.lowercased()
        guard !ChannelNameShortcut.all.contains(where: { $0.matches(lowered) }) else { return names }
        return Array(([name] + names.filter { $0.lowercased() != lowered }).prefix(limit))
    }

    static func save(_ names: [String], to defaults: UserDefaults) {
        defaults.set(names, forKey: key)
    }
}

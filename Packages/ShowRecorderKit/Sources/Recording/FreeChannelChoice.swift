import Foundation

/// The USB Channels (from 1) the operator chose to record on Free, kept between launches. Pro and the Trial
/// record every USB Channel and ignore it. `Entitlement.allowance` decides what is actually recorded.
public enum FreeChannelChoice {
    /// The key it is stored under.
    public static let key = "freeChannelChoice"
    /// What Free records before the operator chooses.
    public static let defaultChoice = [1, 2]

    public static func load(from defaults: UserDefaults = .standard) -> [Int] {
        guard let stored = defaults.array(forKey: key) as? [Int] else { return defaultChoice }
        return stored.filter { $0 > 0 }
    }

    /// The choice after picking `channel` for `slot` of the recorded channels; picking the channel already in the
    /// other slot swaps the two, so the 2 recorded channels stay different.
    public static func picking(_ channel: Int, slot: Int, in recorded: [Int]) -> [Int] {
        var choice = recorded
        if let other = choice.firstIndex(of: channel) {
            choice.swapAt(slot, other)
        } else {
            choice[slot] = channel
        }
        return choice
    }

    public static func save(_ channels: [Int], to defaults: UserDefaults = .standard) {
        defaults.set(channels, forKey: key)
    }
}

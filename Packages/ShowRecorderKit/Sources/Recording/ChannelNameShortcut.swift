import Foundation

/// A chip on the channel names page that fills a row's name. A numbered one adds the next free number
/// ("Vox 1", "Vox 2") so a row of backing vocals needs one tap each. Free text always stays possible.
public struct ChannelNameShortcut: Equatable, Sendable, Hashable {
    /// What the chip says ("Vox"; "Kick").
    public let title: String
    private let base: String
    private let isNumbered: Bool

    private init(_ base: String, numbered: Bool = false) {
        title = base
        self.base = base
        isNumbered = numbered
    }

    /// The name this chip gives, with `taken` the names other rows already have.
    public func name(taken: [String]) -> String {
        guard isNumbered else { return base }
        let used = Set(taken.map { $0.lowercased() })
        var number = 1
        while used.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    /// Whether `lowercasedName` is this chip's name, or (for a numbered chip) its name with a number.
    func matches(_ lowercasedName: String) -> Bool {
        let base = base.lowercased()
        if lowercasedName == base { return true }
        guard isNumbered, lowercasedName.hasPrefix(base + " ") else { return false }
        return Int(lowercasedName.dropFirst(base.count + 1)) != nil
    }

    public static let kick = ChannelNameShortcut("Kick")
    public static let snare = ChannelNameShortcut("Snare")
    public static let hiHat = ChannelNameShortcut("Hi-hat")
    public static let tom = ChannelNameShortcut("Tom", numbered: true)
    public static let overhead = ChannelNameShortcut("Overhead", numbered: true)
    public static let bass = ChannelNameShortcut("Bass")
    public static let guitar = ChannelNameShortcut("Guitar", numbered: true)
    public static let keys = ChannelNameShortcut("Keys", numbered: true)
    public static let leadVox = ChannelNameShortcut("Lead Vox")
    public static let vox = ChannelNameShortcut("Vox", numbered: true)
    public static let bgv = ChannelNameShortcut("BGV", numbered: true)
    public static let playback = ChannelNameShortcut("Playback")
    public static let click = ChannelNameShortcut("Click")

    /// The chips, in the order they are shown.
    public static let all: [ChannelNameShortcut] = [kick, snare, hiHat, tom, overhead, bass, guitar, keys, leadVox, vox, bgv, playback, click]
}

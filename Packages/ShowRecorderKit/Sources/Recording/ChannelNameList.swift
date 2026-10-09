import Foundation

/// One row of the channel names page.
public struct ChannelNameRow: Equatable, Sendable, Identifiable {
    public var id: Int { number }
    /// The USB Channel, from 1.
    public var number: Int
    /// What the operator typed; empty when nothing was.
    public var name: String
    /// What the channel is called without a typed name: the Mixer's name, else "USB 07".
    public var hint: String
}

/// The rows of the channel names page, one per USB Channel.
public enum ChannelNameList {
    /// - Parameters:
    ///   - mixerNames: the Mixer's names by channel index (from 0), only for channels the Mixer named.
    ///   - typed: the names typed so far, by USB Channel number (from 1).
    public static func rows(channelCount: Int, mixerNames: [Int: String], typed: [Int: String]) -> [ChannelNameRow] {
        (1...max(channelCount, 1)).prefix(channelCount).map { number in
            ChannelNameRow(number: number, name: typed[number] ?? "", hint: mixerNames[number - 1] ?? String(format: "USB %02d", number))
        }
    }
}

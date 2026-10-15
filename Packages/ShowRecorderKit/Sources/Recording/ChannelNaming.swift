import Foundation
import MixerLink

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

/// Who names each USB Channel of a Show (#443), keyed from 1. A name the operator typed wins over the Mixer's, which
/// wins over "USB 07". On the screen a typed name always shows; on a Take's files only when the Take may use typed
/// names (Pro or Trial, ADR 0004). A Take that started without Mixer names takes the first ones the Mixer offers.
public struct ChannelNaming: Equatable, Sendable {
    /// The names the operator typed, by USB Channel.
    public private(set) var typed: [Int: String]
    /// True while a Take that started with no Mixer names runs: the first Mixer names offered go on its files.
    private var acceptsLateNames = false
    private var lateMixerNames: [Int: String] = [:]

    public init(typed: [Int: String] = [:]) {
        self.typed = typed
    }

    // MARK: Typing

    /// Names `channel`; a name that is empty or only whitespace is refused (returns false).
    @discardableResult
    public mutating func type(_ name: String, for channel: Int) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        typed[channel] = name
        return true
    }

    /// Takes the typed name off `channel`; returns whether it had one.
    @discardableResult
    public mutating func clear(_ channel: Int) -> Bool {
        typed.removeValue(forKey: channel) != nil
    }

    /// Replaces every typed name: a new Show, a Template or the names copied from the Show before.
    public mutating func replace(with names: [Int: String]) {
        typed = names
    }

    // MARK: Reading, with the Mixer's Sources (the first is USB Channel 1)

    /// The Mixer's own name for `channel`, if it named it.
    public func mixerName(_ channel: Int, sources: [Source]) -> String? {
        sources.indices.contains(channel - 1) && sources[channel - 1].hasMixerName ? sources[channel - 1].name : nil
    }

    /// What `channel` is called without a typed name: the Mixer's name, else "USB 07".
    public func hint(_ channel: Int, sources: [Source]) -> String {
        mixerName(channel, sources: sources) ?? String(format: "USB %02d", channel)
    }

    /// What `channel` is called on the screen.
    public func displayName(_ channel: Int, sources: [Source]) -> String {
        typed[channel] ?? hint(channel, sources: sources)
    }

    /// What the naming box starts with: the typed name, else the Mixer's, else nothing.
    public func editText(_ channel: Int, sources: [Source]) -> String {
        typed[channel] ?? mixerName(channel, sources: sources) ?? ""
    }

    /// The rows of the channel names page, one per USB Channel.
    public func rows(channelCount: Int, sources: [Source]) -> [ChannelNameRow] {
        (1...max(channelCount, 1)).prefix(channelCount).map { number in
            ChannelNameRow(number: number, name: typed[number] ?? "", hint: hint(number, sources: sources))
        }
    }

    // MARK: A Take

    /// The Sources a Take's Stems are named after at record press: the Mixer's, with typed names over them when the
    /// Take may use them. Kept on Free, typed names aren't put on its files.
    public func sources(for mixer: [Source], channelCount: Int, allowance: TakeAllowance?) -> [Source] {
        (0..<channelCount).map { channel in
            var source = mixer.indices.contains(channel) ? mixer[channel] : .fallback(usbChannel: channel + 1)
            if allowance?.namingByHand ?? true, let typed = typed[channel + 1] {
                source.name = typed
                source.hasMixerName = false
            }
            return source
        }
    }

    /// A Take started with `sources`: without any Mixer name, it waits for the first ones offered.
    public mutating func takeStarted(with sources: [Source]) {
        acceptsLateNames = !sources.contains { $0.hasMixerName }
        lateMixerNames = [:]
    }

    /// The Mixer offered names during the Take; the first real ones are kept for its end.
    public mutating func mixerOffered(_ sources: [Source]) {
        guard acceptsLateNames else { return }
        let names = Dictionary(uniqueKeysWithValues: sources.enumerated().filter { $0.element.hasMixerName }.map { ($0.offset + 1, $0.element.name) })
        guard !names.isEmpty else { return }
        lateMixerNames = names
        acceptsLateNames = false
    }

    /// The names to put on a Take's files when it ends: typed ones (when the Take may use them) win over the Mixer's
    /// late ones. Only names that differ from what the files say; `late` are the channels named by the Mixer.
    /// - Parameter onFiles: each USB Channel's name in the Take's files now.
    public mutating func takeEnded(allowance: TakeAllowance?, onFiles: [Int: String]) -> (names: [Int: String], late: Set<Int>) {
        acceptsLateNames = false
        func changes(_ channel: Int, _ name: String) -> Bool { onFiles[channel].map { $0 != name } ?? false }
        let typedNames = allowance?.namingByHand ?? true ? typed : [:]
        let late = lateMixerNames.filter { typedNames[$0.key] == nil && changes($0.key, $0.value) }
        lateMixerNames = [:]
        let names = late.merging(typedNames.filter { changes($0.key, $0.value) }) { _, typed in typed }
        return (names, Set(late.keys))
    }
}

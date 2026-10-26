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
    /// The names typed before on this device, newest first, offered as chips (`SavedChannelNames`).
    public private(set) var saved: [String]
    /// True while a Take that started with no Mixer names runs: the first Mixer names offered go on its files.
    private var acceptsLateNames = false
    private var lateMixerNames: [Int: String] = [:]
    /// The name the Mixer last gave each USB Channel during this Take (or, from the start, the Source the Take began with),
    /// to tell a rename from a repeat.
    private var mixerNames: [Int: String] = [:]
    /// What the Mixer routed to each USB Channel: from the Take's start, or from when the routing was first known (a Mixer Link
    /// that arrived after the press), and after each re-patch.
    private var takeRouting: [Int: String] = [:]

    /// What the Mixer changed on a USB Channel during a Take (#21): the caller logs each on the Take.
    public enum MixerChange: Equatable, Sendable {
        /// The Mixer renamed the channel on the same routing.
        case renamed(channel: Int, from: String, to: String)
        /// The Mixer routed something else to the channel (a re-patch); its Stem holds another Source from here on.
        case repatched(channel: Int, from: String, to: String)
    }

    public init(typed: [Int: String] = [:], saved: [String] = []) {
        self.typed = typed
        self.saved = saved
    }

    // MARK: Typing

    /// Names `channel`; a name that is empty or only whitespace is refused (returns false).
    @discardableResult
    public mutating func type(_ name: String, for channel: Int) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        typed[channel] = name
        saved = SavedChannelNames.adding(name, to: saved)
        return true
    }

    /// Takes the typed name off `channel`; returns whether it had one.
    @discardableResult
    public mutating func clear(_ channel: Int) -> Bool {
        typed.removeValue(forKey: channel) != nil
    }

    /// Fills the names from the Show before: replaces every typed name and remembers them, the lowest channel's name newest.
    /// Returns how many names were copied.
    @discardableResult
    public mutating func copy(_ names: [Int: String]) -> Int {
        replace(with: names)
        for name in names.sorted(by: { $0.key > $1.key }).map(\.value) { saved = SavedChannelNames.adding(name, to: saved) }
        return names.count
    }

    /// Keeps the chips on the device, for the next launch.
    public func persist(to defaults: UserDefaults) {
        SavedChannelNames.save(saved, to: defaults)
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
    /// Take may use them. On Free the Stems get generic names and no colors (#705): kept, typed names and the Mixer's
    /// aren't put on its files. What the Mixer routed to each channel is kept either way.
    public func sources(for mixer: [Source], channelCount: Int, allowance: TakeAllowance?) -> [Source] {
        let mixerNames = allowance?.mixerLinkNames ?? true
        return (0..<channelCount).map { channel in
            var source = mixer.indices.contains(channel) ? mixer[channel] : .fallback(usbChannel: channel + 1)
            if !mixerNames {
                let routedFrom = source.routedFrom
                source = .fallback(usbChannel: channel + 1)
                source.routedFrom = routedFrom
            }
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
        mixerNames = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($0.offset + 1, $0.element.name) })
        takeRouting = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($0.offset + 1, $0.element.routedFrom) }).compactMapValues { $0 }
    }

    /// The Mixer offered `sources` during the Take; the first real names are kept for its end. Returns what changed since the
    /// last offer: re-patches first, then renames. A channel whose routing changed (#21) is a re-patch, not a rename. The first
    /// routing known for a channel is only noted. A re-patch to something the Mixer Link can't name (no `routedFrom`) isn't told
    /// apart from not knowing: it stays a rename.
    public mutating func mixerOffered(_ sources: [Source]) -> [MixerChange] {
        var changes: [MixerChange] = []
        for (index, source) in sources.enumerated() {
            let number = index + 1
            guard let now = source.routedFrom else { continue }
            guard let known = takeRouting[number] else { takeRouting[number] = now; continue }
            guard now != known else { continue }
            changes.append(.repatched(channel: number, from: mixerNames[number] ?? Source.fallback(usbChannel: number).name, to: source.name))
            takeRouting[number] = now
            mixerNames[number] = source.name
        }
        for (index, source) in sources.enumerated() {
            let number = index + 1
            let known = mixerNames[number] ?? Source.fallback(usbChannel: number).name
            guard source.name != known else { continue }
            changes.append(.renamed(channel: number, from: known, to: source.name))
            mixerNames[number] = source.name
        }
        if acceptsLateNames {
            let names = Dictionary(uniqueKeysWithValues: sources.enumerated().filter { $0.element.hasMixerName }.map { ($0.offset + 1, $0.element.name) })
            if !names.isEmpty {
                lateMixerNames = names
                acceptsLateNames = false
            }
        }
        return changes
    }

    /// The names to put on a Take's files when it ends: typed ones (when the Take may use them) win over the Mixer's
    /// late ones. Only names that differ from what the files say; `late` are the channels named by the Mixer.
    /// - Parameter onFiles: each USB Channel's name in the Take's files now.
    public mutating func takeEnded(allowance: TakeAllowance?, onFiles: [Int: String]) -> (names: [Int: String], late: Set<Int>) {
        acceptsLateNames = false
        func changes(_ channel: Int, _ name: String) -> Bool { onFiles[channel].map { $0 != name } ?? false }
        let typedNames = allowance?.namingByHand ?? true ? typed : [:]
        // On Free the Mixer's names never reach the files, late ones included (#705).
        if !(allowance?.mixerLinkNames ?? true) { lateMixerNames = [:] }
        let late = lateMixerNames.filter { typedNames[$0.key] == nil && changes($0.key, $0.value) }
        lateMixerNames = [:]
        let names = late.merging(typedNames.filter { changes($0.key, $0.value) }) { _, typed in typed }
        return (names, Set(late.keys))
    }
}

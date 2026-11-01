import Foundation
import MixerLink

/// A venue's whole setup, saved on this device, so one tap readies a different room (CONTEXT.md, ADR 0004). Starting
/// a Show from it names the Show after it and brings its channel names, Pre-roll, Record to and Mixer. Not the Drive folder.
public struct Template: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    /// The Template's name, which is also the Show's: "Sunday Service" starts "2026-10-12 Sunday Service".
    public var name: String
    public var venue: String?
    /// Typed channel names by USB Channel (from 1).
    public var channelNames: [Int: String]
    /// The Mixer's network name ("Skeyelab XR18"): how the Template finds it again when its address changes.
    public var mixerNetworkName: String?
    /// The address the Mixer last had.
    public var mixerAddress: String
    public var preRollSeconds: Double
    /// The Record to choice (#840); nil in a Template saved before Templates carried it, which leaves the current one.
    public var recordTo: RecordTo?
    /// The USB Channels (from 1) that are not armed (#991); nil in a Template saved before Templates carried it, which leaves the current choice. The app applies it (and saves it) with the Pre-roll and the Mixer.
    public var notArmedChannels: Set<Int>?

    public init(
        name: String, venue: String?, channelNames: [Int: String],
        mixerNetworkName: String?, mixerAddress: String, preRollSeconds: Double, recordTo: RecordTo? = nil,
        notArmedChannels: Set<Int>? = nil
    ) {
        self.name = name
        self.venue = venue
        self.channelNames = channelNames
        self.mixerNetworkName = mixerNetworkName
        self.mixerAddress = mixerAddress
        self.preRollSeconds = preRollSeconds
        self.recordTo = recordTo
        self.notArmedChannels = notArmedChannels
    }

    /// Where to connect: a Mixer found with this Template's network name, wherever it is now, or else the saved
    /// address.
    public func connectAddress(found: [FoundMixer]) -> String {
        guard let name = mixerNetworkName, let match = found.first(where: { $0.identity.networkName == name }) else {
            return mixerAddress
        }
        return match.host
    }

    /// A Template from a past Show's setup (#34): its channel names and venue, named like the Show without the date
    /// ("2026-10-09 Youth Night" gives "Youth Night"). Shows don't keep a Mixer, Pre-roll or Record to, so those are
    /// today's. Nil when the Show's file can't be read.
    public static func fromShow(folder: URL, mixerNetworkName: String?, mixerAddress: String, preRollSeconds: Double, recordTo: RecordTo? = nil) -> Template? {
        guard let file = ShowFile.read(from: folder) else { return nil }
        let datePrefix = #/^\d{4}-\d{2}-\d{2} /#
        let name = file.name.replacing(datePrefix, with: "")
        let names = file.channelNames?.reduce(into: [Int: String]()) { if let number = Int($1.key) { $0[number] = $1.value } } ?? [:]
        return Template(
            name: name, venue: file.venue, channelNames: names,
            mixerNetworkName: mixerNetworkName, mixerAddress: mixerAddress, preRollSeconds: preRollSeconds, recordTo: recordTo)
    }

    func withID(_ id: UUID) -> Template {
        var copy = self
        copy.id = id
        return copy
    }
}

/// The Templates on this device, listed by name.
public struct TemplateStore {
    /// The key they are stored under.
    public static let key = "templates"
    /// The key of the default Template's id.
    public static let defaultKey = "defaultTemplate"
    /// Where a store that couldn't be read is kept aside, so a save never erases it (#325).
    public static let unreadableKey = "templates.unreadable"
    private let defaults: UserDefaults
    public private(set) var templates: [Template]
    public private(set) var defaultID: Template.ID?
    /// The stored Templates couldn't be read this launch: they were kept aside and the list starts empty.
    public private(set) var couldNotRead = false

    /// The Template that readies the next Show at launch when none is open (#34).
    public var defaultTemplate: Template? { templates.first { $0.id == defaultID } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var stored: [Template] = []
        if let data = defaults.data(forKey: Self.key) {
            if let decoded = try? JSONDecoder().decode([Template].self, from: data) {
                stored = decoded
            } else {
                // Keep what couldn't be read aside (the first copy wins), so the next save can't erase it.
                if defaults.data(forKey: Self.unreadableKey) == nil { defaults.set(data, forKey: Self.unreadableKey) }
                couldNotRead = true
            }
        }
        templates = Self.sorted(stored)
        defaultID = defaults.string(forKey: Self.defaultKey).flatMap(UUID.init(uuidString:))
    }

    /// Makes `id` the default Template, or none.
    public mutating func setDefault(_ id: Template.ID?) {
        defaultID = id
        defaults.set(id?.uuidString, forKey: Self.defaultKey)
    }

    /// Adds `template`, or replaces the one with its id.
    public mutating func save(_ template: Template) {
        templates.removeAll { $0.id == template.id }
        templates = Self.sorted(templates + [template])
        persist()
    }

    public mutating func rename(_ id: Template.ID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var template = templates.first(where: { $0.id == id }) else { return }
        template.name = name
        save(template)
    }

    public mutating func delete(_ id: Template.ID) {
        if defaultID == id { setDefault(nil) }
        templates.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(templates), forKey: Self.key)
    }

    private static func sorted(_ templates: [Template]) -> [Template] {
        templates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Whether Templates can be used right now. A Pro feature (ADR 0004), but only once Pro is offered, like the limits
/// (#60); never during a Take, since a Template starts a Show.
public enum TemplateAccess: Equatable, Sendable {
    case usable
    /// Free: listed, not usable. Nothing saved is deleted.
    case proOnly
    case takeRunning

    /// Built by `License.templateAccess(isRecording:)`.
    init(limits: Bool, isRecording: Bool) {
        if isRecording {
            self = .takeRunning
        } else if limits {
            self = .proOnly
        } else {
            self = .usable
        }
    }

    /// What the Show sheet says under the Templates, when they can't be used.
    public var note: String? {
        switch self {
        case .usable: nil
        case .proOnly: "Templates are part of Pro. Your saved Templates are kept."
        case .takeRunning: "A Template can't be used during a Take."
        }
    }
}

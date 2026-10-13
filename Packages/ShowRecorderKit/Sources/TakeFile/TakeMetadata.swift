import Destinations
import Foundation

/// What a Take's `Take.json` holds: when and how it was recorded, and each USB Channel's Stem and
/// Source as frozen at record time. Written when the Take starts, so it survives a crash.
public struct TakeMetadata: Codable, Equatable, Sendable {
    public struct USBChannel: Codable, Equatable, Sendable {
        public struct Color: Codable, Equatable, Sendable {
            public var hue: String
            public var inverted: Bool

            public init(hue: String, inverted: Bool) {
                self.hue = hue
                self.inverted = inverted
            }
        }

        public var usbChannel: Int
        public var stemFile: String
        public var name: String
        public var hasMixerName: Bool
        /// True when the Take started with no Mixer name for this channel and the Mixer's arrived during it.
        /// Nil otherwise, and in Takes made before late names existed.
        public var nameArrivedLate: Bool?
        public var color: Color
        public var muted: Bool?
        public var fader: Float?
        public var inputSource: Int?
        /// This channel's loudest peak during the Take (from the press, not the Pre-roll), and its average
        /// level, in dBFS: the power average of the VU levels (see `TakeLevels`). Nil in Takes made before
        /// levels were recorded; -80 for a silent channel.
        public var peakDbfs: Double?
        public var averageDbfs: Double?

        public init(
            usbChannel: Int, stemFile: String, name: String, hasMixerName: Bool, nameArrivedLate: Bool? = nil, color: Color,
            muted: Bool? = nil, fader: Float? = nil, inputSource: Int? = nil, peakDbfs: Double? = nil, averageDbfs: Double? = nil
        ) {
            self.usbChannel = usbChannel
            self.stemFile = stemFile
            self.name = name
            self.hasMixerName = hasMixerName
            self.nameArrivedLate = nameArrivedLate
            self.color = color
            self.muted = muted
            self.fader = fader
            self.inputSource = inputSource
            self.peakDbfs = peakDbfs
            self.averageDbfs = averageDbfs
        }
    }

    public var show: String
    public var take: Int
    public var startedAt: Date
    public var sampleRate: Int
    /// Samples since local midnight at the start of the Take, as in every Stem's bext.
    public var timeReference: UInt64
    public var usbChannels: [USBChannel]
    /// Markers placed during the Take, in the order they were placed.
    public var markers: [Marker] = []

    /// How many frames at the start of the Take (and of every Stem) are Pre-roll: audio from before record
    /// was pressed. `timeReference` is the wall-clock start of those frames. Nil when there was none.
    public var preRollFrames: Int?

    /// Stretches of the Take missing from one Copy, held there as silence, in order.
    public var gaps: [Gap] = []

    /// A stretch of the Take, in samples from its start, missing from one Copy.
    public struct Gap: Codable, Equatable, Sendable {
        public var copy: DestinationKind
        public var start: Int
        public var end: Int

        public init(copy: DestinationKind, start: Int, end: Int) {
            self.copy = copy
            self.start = start
            self.end = end
        }
    }

    /// Stretches of one Copy that were lost because its writer couldn't keep up, written as silence of the
    /// exact length so the Stems stay as long as the Take. Unlike a Gap, Repair doesn't fill them (yet).
    public var dropouts: [Dropout] = []

    public struct Dropout: Codable, Equatable, Sendable {
        public var copy: DestinationKind
        public var start: Int
        public var end: Int

        public init(copy: DestinationKind, start: Int, end: Int) {
            self.copy = copy
            self.start = start
            self.end = end
        }
    }

    /// Renames made on the Mixer during the Take, in the order they happened. The Stems keep the names they
    /// started with (or, for a Take that started without Mixer names, got when it ended). Nil when there
    /// were none, and in Takes made before the rename log existed.
    public var renames: [Rename]?

    /// A Source renamed on the Mixer at a point in the Take, in samples from its start.
    public struct Rename: Codable, Equatable, Sendable {
        public var position: Int
        public var usbChannel: Int
        public var from: String
        public var to: String

        public init(position: Int, usbChannel: Int, from: String, to: String) {
            self.position = position
            self.usbChannel = usbChannel
            self.from = from
            self.to = to
        }
    }

    /// What Repair did about each Gap, once the Take had ended.
    public var repairs: [Repair] = []

    public struct Repair: Codable, Equatable, Sendable {
        public enum Outcome: String, Codable, Sendable {
            case repaired
            /// The other Copy didn't have those samples either, or they couldn't be copied.
            case failed

            /// "Repaired" or "Repair failed", as the operator reads it.
            public var word: String {
                switch self {
                case .repaired: "Repaired"
                case .failed: "Repair failed"
                }
            }
        }

        public var copy: DestinationKind
        public var start: Int
        public var end: Int
        public var outcome: Outcome

        public init(copy: DestinationKind, start: Int, end: Int, outcome: Outcome) {
            self.copy = copy
            self.start = start
            self.end = end
            self.outcome = outcome
        }
    }

    /// How a Copy of the Take ended up, from its Gaps and what Repair did about them.
    public func outcome(ofCopy copy: DestinationKind) -> CopyOutcome {
        guard gaps.contains(where: { $0.copy == copy }) else { return .complete }
        let results = repairs.filter { $0.copy == copy }
        if results.isEmpty { return .hasGaps }
        return results.contains { $0.outcome != .repaired } ? .repairFailed : .repaired
    }

    /// A named point in the Take, in samples from its start.
    public struct Marker: Codable, Equatable, Sendable {
        public enum Origin: Codable, Equatable, Sendable {
            case `operator`
            /// Placed by the recorder where a Copy's audio was lost.
            case dropout
            /// A kind from a newer ShowRecorder (such as 1.1's gain and routing Markers), kept as written: the Take still
            /// opens, and saving it keeps the kind. Not the operator's, so it can't be renamed here. Only for text this
            /// version doesn't know: make an Origin from text with `init(rawValue:)`.
            case other(String)

            /// What `Take.json` stores.
            public var rawValue: String {
                switch self {
                case .operator: "operator"
                case .dropout: "dropout"
                case .other(let text): text
                }
            }

            public init(rawValue: String) {
                self = [Self.operator, .dropout].first { $0.rawValue == rawValue } ?? .other(rawValue)
            }

            public init(from decoder: any Decoder) throws {
                self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(rawValue)
            }
        }

        public var position: Int
        public var name: String
        public var origin: Origin

        public init(position: Int, name: String, origin: Origin) {
            self.position = position
            self.name = name
            self.origin = origin
        }
    }

    public static let fileName = "Take.json"

    /// "Take 01": a Take's name, and the name of its folder in every Copy.
    public static func name(take: Int) -> String {
        String(format: "Take %02d", take)
    }

    /// Fields from a newer ShowRecorder, kept from `read` to `write`. Nil in a Take this version wrote.
    public private(set) var unknownFields: UnknownFields?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case show, take, startedAt, sampleRate, timeReference, usbChannels, markers, gaps, repairs, preRollFrames, dropouts, renames
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        show = try c.decode(String.self, forKey: .show)
        take = try c.decode(Int.self, forKey: .take)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        sampleRate = try c.decode(Int.self, forKey: .sampleRate)
        timeReference = try c.decode(UInt64.self, forKey: .timeReference)
        usbChannels = try c.decode([USBChannel].self, forKey: .usbChannels)
        markers = try c.decodeIfPresent([Marker].self, forKey: .markers) ?? []  // Takes recorded before Markers existed
        gaps = try c.decodeIfPresent([Gap].self, forKey: .gaps) ?? []  // Takes recorded before Gaps existed
        repairs = try c.decodeIfPresent([Repair].self, forKey: .repairs) ?? []
        preRollFrames = try c.decodeIfPresent(Int.self, forKey: .preRollFrames)
        dropouts = try c.decodeIfPresent([Dropout].self, forKey: .dropouts) ?? []  // Takes recorded before Dropouts existed
        renames = try c.decodeIfPresent([Rename].self, forKey: .renames)
    }

    public init(show: String, take: Int, startedAt: Date, sampleRate: Int, timeReference: UInt64, usbChannels: [USBChannel], markers: [Marker] = []) {
        self.show = show
        self.take = take
        self.startedAt = startedAt
        self.sampleRate = sampleRate
        self.timeReference = timeReference
        self.usbChannels = usbChannels
        self.markers = markers
    }

    /// Writes `Take.json` into `takeFolder`, replacing any earlier one.
    public func write(to takeFolder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try (unknownFields?.merged(into: data) ?? data).write(to: takeFolder.appending(path: Self.fileName), options: .atomic)
    }

    /// Reads `Take.json` from `takeFolder`. Throws when it is missing or can't be decoded.
    public static func read(fromTakeFolder takeFolder: URL) throws -> TakeMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: takeFolder.appending(path: fileName))
        var metadata = try decoder.decode(TakeMetadata.self, from: data)
        metadata.unknownFields = UnknownFields.find(in: data, known: Set(CodingKeys.allCases.map(\.rawValue)))
        return metadata
    }
}

/// How one Copy of an ended Take stands.
public enum CopyOutcome: String, Sendable, Equatable {
    case complete
    case hasGaps
    case repaired
    case repairFailed

    /// The outcome as the operator reads it: "complete", "has Gaps", "Repaired" or "Repair failed".
    public var word: String {
        switch self {
        case .complete: "complete"
        case .hasGaps: "has Gaps"
        case .repaired: TakeMetadata.Repair.Outcome.repaired.word
        case .repairFailed: TakeMetadata.Repair.Outcome.failed.word
        }
    }
}

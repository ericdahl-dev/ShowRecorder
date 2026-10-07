import Destinations
import Foundation
import MixerLink

/// What a Take's `Take.json` holds: when and how it was recorded, and each USB Channel's Stem and
/// Source as frozen at record time. Written when the Take starts, so it survives a crash.
public struct TakeMetadata: Codable, Equatable, Sendable {
    public struct USBChannel: Codable, Equatable, Sendable {
        public struct Color: Codable, Equatable, Sendable {
            public var hue: String
            public var inverted: Bool
        }

        public var usbChannel: Int
        public var stemFile: String
        public var name: String
        public var hasMixerName: Bool
        public var color: Color
        public var muted: Bool?
        public var fader: Float?
        public var inputSource: Int?
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

    /// What Repair did about each Gap, once the Take had ended.
    public var repairs: [Repair] = []

    public struct Repair: Codable, Equatable, Sendable {
        public enum Outcome: String, Codable, Sendable {
            case repaired
            /// The other Copy didn't have those samples either, or they couldn't be copied.
            case failed
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
        public enum Origin: String, Codable, Sendable {
            case `operator`
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

    static let fileName = "Take.json"

    enum CodingKeys: String, CodingKey {
        case show, take, startedAt, sampleRate, timeReference, usbChannels, markers, gaps, repairs, preRollFrames
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
    }

    init(show: String, take: Int, startedAt: Date, sampleRate: Int, timeReference: UInt64, usbChannels: [USBChannel], markers: [Marker] = []) {
        self.show = show
        self.take = take
        self.startedAt = startedAt
        self.sampleRate = sampleRate
        self.timeReference = timeReference
        self.usbChannels = usbChannels
        self.markers = markers
    }

    func write(to takeFolder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: takeFolder.appending(path: Self.fileName), options: .atomic)
    }
}

extension TakeMetadata.USBChannel {
    init(usbChannel: Int, stemFile: String, source: Source) {
        self.init(
            usbChannel: usbChannel,
            stemFile: stemFile,
            name: source.name,
            hasMixerName: source.hasMixerName,
            color: Color(hue: source.color.hue.name, inverted: source.color.inverted),
            muted: source.isMuted,
            fader: source.fader,
            inputSource: source.inputSource)
    }
}

/// How one Copy of an ended Take stands.
public enum CopyOutcome: String, Sendable, Equatable {
    case complete
    case hasGaps
    case repaired
    case repairFailed
}

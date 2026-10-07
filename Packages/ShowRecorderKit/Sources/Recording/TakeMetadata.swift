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

    static let fileName = "Take.json"

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

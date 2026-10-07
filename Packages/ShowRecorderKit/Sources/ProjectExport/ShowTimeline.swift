import MixerLink

/// What a DAW project needs to know about a Show: its USB Channels, named and colored from the
/// latest Take, and its Takes in order, each with its length and Stems.
///
/// Built from the Show folder by the recorder; exporters only render it, so a new DAW format
/// (Logic, AAF) is a new `ProjectExporter`, not a new reader. Markers (#25) will be added to `Take`.
public struct ShowTimeline: Equatable, Sendable {
    public struct USBChannel: Equatable, Sendable {
        /// 1-based.
        public var number: Int
        public var name: String
        public var color: MixerColor

        public init(number: Int, name: String, color: MixerColor) {
            self.number = number
            self.name = name
            self.color = color
        }
    }

    public struct Stem: Equatable, Sendable {
        public var usbChannel: Int
        /// Path relative to the Show folder, with "/" separators, e.g. "Take 01/01 Kick.wav".
        public var path: String
        /// The Source name frozen into this Take.
        public var name: String

        public init(usbChannel: Int, path: String, name: String) {
            self.usbChannel = usbChannel
            self.path = path
            self.name = name
        }
    }

    public struct Take: Equatable, Sendable {
        public var number: Int
        public var sampleRate: Int
        /// The Take's length in samples, read from its Stems.
        public var frameCount: UInt64
        public var stems: [Stem]
        /// Markers placed during the Take, in samples from its start.
        public var markers: [Marker]

        public init(number: Int, sampleRate: Int, frameCount: UInt64, stems: [Stem], markers: [Marker] = []) {
            self.number = number
            self.sampleRate = sampleRate
            self.frameCount = frameCount
            self.stems = stems
            self.markers = markers
        }

        public struct Marker: Equatable, Sendable {
            public var position: Int
            public var name: String

            public init(position: Int, name: String) {
                self.position = position
                self.name = name
            }
        }

        public var duration: Double { sampleRate > 0 ? Double(frameCount) / Double(sampleRate) : 0 }
    }

    public var showName: String
    /// In USB Channel order.
    public var usbChannels: [USBChannel]
    /// In Take order.
    public var takes: [Take]

    public init(showName: String, usbChannels: [USBChannel], takes: [Take]) {
        self.showName = showName
        self.usbChannels = usbChannels
        self.takes = takes
    }
}

/// Renders a Show as a project file for one DAW.
public protocol ProjectExporter: Sendable {
    /// The project file's extension, e.g. "RPP". The file is named "<Show name>.<extension>".
    var fileExtension: String { get }
    func project(for show: ShowTimeline) -> [UInt8]
}

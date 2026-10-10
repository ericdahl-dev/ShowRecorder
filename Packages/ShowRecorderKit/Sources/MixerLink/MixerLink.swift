/// Where a Mixer listens for OSC. X-Air mixers use UDP port 10024.
public struct MixerEndpoint: Equatable, Sendable {
    public var host: String
    public var port: UInt16

    public init(host: String, port: UInt16 = 10024) {
        self.host = host
        self.port = port
    }
}

/// What a Mixer says about itself.
public struct MixerIdentity: Equatable, Sendable {
    public var networkName: String
    public var model: String
    public var firmware: String

    public init(networkName: String, model: String, firmware: String) {
        self.networkName = networkName
        self.model = model
        self.firmware = firmware
    }
}

/// What one Mixer model can do over USB, as its driver knows it.
public struct MixerCapabilities: Equatable, Sendable {
    /// USB Channels the Mixer sends to the recorder. Nil when the model sends no multichannel USB
    /// audio or the driver doesn't know the model.
    public var usbChannelCount: Int?
    /// How many USB Channels, from the first, the driver can give a Source name and color.
    public var nameableUSBChannelCount: Int

    public init(usbChannelCount: Int?, nameableUSBChannelCount: Int) {
        self.usbChannelCount = usbChannelCount
        self.nameableUSBChannelCount = nameableUSBChannelCount
    }
}

/// Why the Mixer Link is down, in terms an operator can act on.
public enum MixerLinkProblem: Error, Equatable, Sendable {
    /// Nothing answered at that address: wrong IP, or the Mixer is off.
    case noReply(host: String)
    /// The device isn't on a network that can reach the Mixer.
    case networkUnreachable
    /// iOS local network access is turned off for ShowRecorder.
    case localNetworkDenied
    /// The address typed in isn't a valid host.
    case invalidAddress(String)
    case other(String)

    public var message: String {
        switch self {
        case .noReply(let host):
            "No mixer answered at \(host). Check the IP address, and that this device is on the same network as the mixer."
        case .networkUnreachable:
            "This device isn't connected to a network that can reach the mixer. Join the mixer's Wi-Fi network."
        case .localNetworkDenied:
            "ShowRecorder isn't allowed to use the local network. Turn on Local Network for ShowRecorder in Settings › Privacy & Security."
        case .invalidAddress(let text):
            "\"\(text)\" isn't a valid IP address."
        case .other(let description):
            "The mixer connection failed: \(description)"
        }
    }
}

/// Talks to one kind of Mixer. X-Air first; X32/M32 can follow with the same shape.
public protocol MixerDriver: Sendable {
    func identify() async throws(MixerLinkProblem) -> MixerIdentity
    /// What the identified model sends over USB and how many of its USB Channels this driver can name.
    func capabilities(for identity: MixerIdentity) -> MixerCapabilities
    /// One Source per USB Channel, in USB Channel order.
    func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source]
    /// Asks the Mixer to keep pushing changes for a while longer (X-Air: /xremote lasts 10 seconds) and
    /// checks that it is still there. Throws when it doesn't answer.
    func renewLiveUpdates() async throws(MixerLinkProblem)
    /// The Source changes the Mixer pushes while live updates are renewed. Ends when the driver goes away.
    func sourceChanges() -> AsyncStream<SourceChange>
}

/// A name or color the Mixer changed on one USB Channel's Source. Nil fields did not change.
public struct SourceChange: Equatable, Sendable {
    public var usbChannel: Int
    public var name: String?
    public var color: MixerColor?

    public init(usbChannel: Int, name: String? = nil, color: MixerColor? = nil) {
        self.usbChannel = usbChannel
        self.name = name
        self.color = color
    }
}

/// What the Mixer routes to a USB Channel, as shown on its meter and in its Stem's name.
public struct Source: Equatable, Sendable {
    public var name: String
    public var color: MixerColor
    /// False when the Mixer had no name for it and `name` is the USB Channel default ("USB 07").
    public var hasMixerName: Bool
    /// Mixer state at the time it was read. Nil when the Mixer didn't report it.
    public var isMuted: Bool?
    /// Fader position, 0...1.
    public var fader: Float?
    /// The Mixer's input source index for the channel.
    public var inputSource: Int?

    public init(name: String, color: MixerColor, hasMixerName: Bool = true, isMuted: Bool? = nil, fader: Float? = nil, inputSource: Int? = nil) {
        self.name = name
        self.color = color
        self.hasMixerName = hasMixerName
        self.isMuted = isMuted
        self.fader = fader
        self.inputSource = inputSource
    }

    /// The default for USB Channel `number` (1-based) when the Mixer gives no name.
    public static func fallback(usbChannel number: Int, color: MixerColor = .off) -> Source {
        Source(name: String(format: "USB %02d", number), color: color, hasMixerName: false)
    }
}

/// A Mixer scribble-strip color. "Inverted" is the X-Air style with colored background.
public struct MixerColor: Equatable, Sendable {
    public enum Hue: Int, Sendable, CaseIterable {
        case off, red, green, yellow, blue, magenta, cyan, white

        public var name: String { String(describing: self) }
    }

    public var hue: Hue
    public var inverted: Bool

    public init(hue: Hue, inverted: Bool) {
        self.hue = hue
        self.inverted = inverted
    }

    public static let off = MixerColor(hue: .off, inverted: false)

    /// X-Air color index: 0–7 are the hues, 8–15 the same hues inverted.
    public init(xAirIndex index: Int32) {
        let clamped = Int(max(0, min(15, index)))
        self.init(hue: Hue(rawValue: clamped % 8) ?? .off, inverted: clamped >= 8)
    }
}

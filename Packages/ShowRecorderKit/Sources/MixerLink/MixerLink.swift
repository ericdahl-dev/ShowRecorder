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
    /// One Source per USB Channel, in USB Channel order.
    func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source]
}

/// What the Mixer routes to a USB Channel, as shown on its meter and in its Stem's name.
public struct Source: Equatable, Sendable {
    public var name: String
    public var color: MixerColor
    /// False when the Mixer had no name for it and `name` is the USB Channel default ("USB 07").
    public var hasMixerName: Bool

    public init(name: String, color: MixerColor, hasMixerName: Bool = true) {
        self.name = name
        self.color = color
        self.hasMixerName = hasMixerName
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

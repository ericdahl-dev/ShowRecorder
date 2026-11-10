import Foundation
import OSC
import Synchronization

/// A family of mixers the Mixer Link can talk to, recognized from the audio interface's name (#365). Mixer Link is
/// offered only for one of these; any other input (a built-in mic, the Demo signal, an EVO 4, a DJM) gets none.
/// Mixer packs (#412) unlock by family too.
public enum MixerFamily: Sendable, Equatable, CaseIterable {
    /// XR18, MR18 (and the XR12 and XR16, which send no multichannel USB). Seen on the Mac as "X18/XR18".
    case xAir
    /// X32 and M32 with a USB card. The names are what Behringer and Midas call their cards ("X-USB", "X-LIVE",
    /// "DN32-USB", "DN32-LIVE"); not yet seen on a real card (#503).
    case x32
    /// Behringer WING, WING Compact and WING Rack, with 48 USB Channels built in (#417). Offered only where the app
    /// turns it on (`offersWing`, from `WingAvailability`); not yet seen on a real WING.
    case wing

    /// The families offered in this run of the app: the X Air and the X32 always, the WING only once the app has turned
    /// it on. Find mixers, detection and the interface names all go by this list, so a build without the WING never
    /// asks for one.
    public static var allCases: [MixerFamily] { offered(wing: offersWing) }

    /// The families offered with or without the WING, in the order detection asks them. The X Air stays first: its
    /// port is the default for an address typed without one.
    public static func offered(wing: Bool) -> [MixerFamily] {
        wing ? [.xAir, .x32, .wing] : [.xAir, .x32]
    }

    /// Whether the WING is offered (#417). Off until the app sets it at launch from `WingAvailability`.
    public static var offersWing: Bool {
        get { wingSwitch.withLock { $0 } }
        set { wingSwitch.withLock { $0 = newValue } }
    }

    private static let wingSwitch = Mutex(false)

    public init?(audioInterfaceName name: String) {
        self.init(audioInterfaceName: name, offering: Self.allCases)
    }

    /// The family of an audio interface named `name`, among `families`.
    public init?(audioInterfaceName name: String, offering families: [MixerFamily]) {
        let name = name.uppercased()
        let family: MixerFamily? = if ["XR18", "MR18", "X18"].contains(where: name.contains) {
            .xAir
        } else if ["X-USB", "X-LIVE", "X32", "M32", "DN32"].contains(where: name.contains) {  // DN32 covers DN32-USB and DN32-LIVE (#503)
            .x32
        } else if name.contains("WING") {
            .wing
        } else {
            nil
        }
        guard let family, families.contains(family) else { return nil }
        self = family
    }
}

/// How Find mixers and the Mixer Link ask a family's Mixer who it is (#442): the port it listens on, the datagram to
/// send there, and how to read its reply.
public struct MixerProbe: Sendable {
    public let port: UInt16
    public let request: [UInt8]
    /// The Mixer's identity from one reply datagram; nil for anything else.
    public let identity: @Sendable ([UInt8]) -> MixerIdentity?

    public init(port: UInt16, request: [UInt8], identity: @escaping @Sendable ([UInt8]) -> MixerIdentity?) {
        self.port = port
        self.request = request
        self.identity = identity
    }

    /// Behringer's `/xinfo` on `port`, which the X Air and the X32 both answer.
    public static func xinfo(port: UInt16) -> MixerProbe {
        MixerProbe(port: port, request: OSCMessage("/xinfo").encoded()) { data in
            (try? OSCPacket(decoding: data))?.messages.first { $0.address == "/xinfo" }.flatMap(xinfoIdentity)
        }
    }

    /// An `/xinfo` reply: the Mixer's IP, network name, model and firmware.
    static func xinfoIdentity(_ message: OSCMessage) -> MixerIdentity? {
        let strings = message.arguments.compactMap { if case .string(let value) = $0 { value } else { nil } }
        guard strings.count >= 4 else { return nil }
        return MixerIdentity(networkName: strings[1], model: strings[2], firmware: strings[3])
    }

    /// The WING's discovery knock (#417): the plain text `WING?` to UDP port 2222, as Maillot's WING Remote Protocols
    /// document starts every conversation, and as his wingemul answers. The reply is plain text; a WING's OSC `/?`
    /// reply (port 2223) carries the same text and is read the same way.
    public static let wing = MixerProbe(port: 2222, request: Array("WING?".utf8)) { data in
        if let message = (try? OSCPacket(decoding: data))?.messages.first(where: { $0.address == "/?" }),
           case .string(let text)? = message.arguments.first {
            return wingIdentity(text)
        }
        return wingIdentity(String(decoding: data, as: UTF8.self))
    }

    /// A WING's identity text, "WING,<ip>,<name>,<model>,<serial>,<firmware>" (WING Remote Protocols, Maillot, V3.0.5-1),
    /// as it answers `/?` on port 2223 and `WING?` on port 2222. Nil for any other text.
    static func wingIdentity(_ text: String) -> MixerIdentity? {
        let fields = text.split(separator: ",", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 6, fields[0] == "WING" else { return nil }
        return MixerIdentity(networkName: fields[2], model: fields[3],
                             firmware: fields[5].trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines)))
    }
}

/// The registry of families the Mixer Link can talk to (#442): a new family is a case here and its driver.
extension MixerFamily {
    public var probe: MixerProbe {
        switch self {
        case .xAir: .xinfo(port: 10024)
        case .x32: .xinfo(port: 10023)
        case .wing: .wing
        }
    }

    /// Every offered family's probe, in the order detection asks them.
    public static var probes: [MixerProbe] { allCases.map(\.probe) }

    public func makeDriver(endpoint: MixerEndpoint, timeout: Duration) -> any MixerDriver {
        switch self {
        case .xAir: XAirDriver(endpoint: endpoint, timeout: timeout)
        case .x32: X32Driver(endpoint: endpoint, timeout: timeout)
        case .wing: WingDriver(endpoint: endpoint, timeout: timeout)
        }
    }

    /// The family whose driver reads `model`, as a Mixer names itself. A model no family claims is read as an X Air,
    /// since the X Air driver reads any Behringer that answers `/xinfo` the X Air's way. A WING names itself
    /// "ngc-full" (the full-size desk) or, per Maillot's document, "wing-rack", "wing-compact" or "wing-bk".
    public static func reading(model: String) -> MixerFamily {
        let model = model.uppercased()
        if model.hasPrefix("X32") || model.hasPrefix("M32") { return .x32 }
        if model.hasPrefix("NGC") || model.hasPrefix("WING") { return .wing }
        return .xAir
    }
}

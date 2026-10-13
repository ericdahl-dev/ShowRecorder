import OSC

/// A family of mixers the Mixer Link can talk to, recognized from the audio interface's name (#365). Mixer Link is
/// offered only for one of these; any other input (a built-in mic, the Demo signal, an EVO 4, a DJM) gets none.
/// Mixer packs (#412) unlock by family too.
public enum MixerFamily: Sendable, Equatable, CaseIterable {
    /// XR18, MR18 (and the XR12 and XR16, which send no multichannel USB). Seen on the Mac as "X18/XR18".
    case xAir
    /// X32 and M32 with a USB card. The names are what Behringer and Midas call their cards ("X-USB", "DN32-USB");
    /// not yet seen on a real card.
    case x32

    public init?(audioInterfaceName name: String) {
        let name = name.uppercased()
        if ["XR18", "MR18", "X18"].contains(where: name.contains) {
            self = .xAir
        } else if ["X-USB", "X-LIVE", "X32", "M32", "DN32"].contains(where: name.contains) {  // DN32 covers DN32-USB and DN32-LIVE (#503)
            self = .x32
        } else {
            return nil
        }
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
}

/// The registry of families the Mixer Link can talk to (#442): a new family is a case here and its driver.
extension MixerFamily {
    public var probe: MixerProbe {
        switch self {
        case .xAir: .xinfo(port: 10024)
        case .x32: .xinfo(port: 10023)
        }
    }

    /// Every family's probe, in the order detection asks them.
    public static var probes: [MixerProbe] { allCases.map(\.probe) }

    public func makeDriver(endpoint: MixerEndpoint, timeout: Duration) -> any MixerDriver {
        switch self {
        case .xAir: XAirDriver(endpoint: endpoint, timeout: timeout)
        case .x32: X32Driver(endpoint: endpoint, timeout: timeout)
        }
    }

    /// The family whose driver reads `model`, as a Mixer names itself. A model no family claims is read as an X Air,
    /// since the X Air driver reads any Behringer that answers `/xinfo` the X Air's way.
    public static func reading(model: String) -> MixerFamily {
        let model = model.uppercased()
        return model.hasPrefix("X32") || model.hasPrefix("M32") ? .x32 : .xAir
    }
}

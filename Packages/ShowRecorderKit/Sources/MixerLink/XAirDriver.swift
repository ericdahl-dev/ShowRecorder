import OSC

/// The X-Air driver (XR12/XR16/XR18, MR18) over OSC on UDP port 10024.
public final class XAirDriver: MixerDriver {
    private let client: OSCUDPClient
    private let timeout: Duration

    public init(endpoint: MixerEndpoint, timeout: Duration = .seconds(1.5)) {
        client = OSCUDPClient(endpoint: endpoint)
        self.timeout = timeout
    }

    /// `/xinfo` answers with the Mixer's IP, network name, model and firmware.
    public func identify() async throws(MixerLinkProblem) -> MixerIdentity {
        let reply = try await client.request(OSCMessage("/xinfo"), timeout: timeout)
        let strings = reply.arguments.compactMap { if case .string(let value) = $0 { value } else { nil } }
        guard strings.count >= 4 else { throw .other("The mixer's /xinfo reply was incomplete") }
        return MixerIdentity(networkName: strings[1], model: strings[2], firmware: strings[3])
    }

    /// USB Channels 1–16 carry input channels 1–16; 17–18 carry the aux return (left and right).
    /// The Mixer's actual USB routing is read in #20; until then this is the XR18's default.
    public func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        var sources: [Source] = []
        guard usbChannelCount > 0 else { return sources }
        for usbChannel in 1...usbChannelCount {
            let base = usbChannel <= 16 ? String(format: "/ch/%02d/config", usbChannel) : "/rtn/aux/config"
            let name = try await string(at: base + "/name")
            let color = MixerColor(xAirIndex: try await int(at: base + "/color"))
            sources.append(name.isEmpty
                ? .fallback(usbChannel: usbChannel, color: color)
                : Source(name: name, color: color))
        }
        return sources
    }

    private func string(at address: String) async throws(MixerLinkProblem) -> String {
        let reply = try await client.request(OSCMessage(address), timeout: timeout)
        guard case .string(let value)? = reply.arguments.first else { throw .other("\(address) didn't return a name") }
        return value
    }

    private func int(at address: String) async throws(MixerLinkProblem) -> Int32 {
        let reply = try await client.request(OSCMessage(address), timeout: timeout)
        guard case .int(let value)? = reply.arguments.first else { throw .other("\(address) didn't return a number") }
        return value
    }
}

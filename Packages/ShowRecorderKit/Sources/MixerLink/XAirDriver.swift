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

    /// The XR18 and MR18 send 18 USB Channels; the XR12 and XR16 send no multichannel USB audio. An
    /// X-Air model not listed here has no known USB Channel count and is named like the XR18.
    public func capabilities(for identity: MixerIdentity) -> MixerCapabilities {
        switch identity.model.uppercased() {
        case "XR18", "MR18": MixerCapabilities(usbChannelCount: 18, nameableUSBChannelCount: Self.nameableUSBChannelCount)
        case "XR12", "XR16": MixerCapabilities(usbChannelCount: nil, nameableUSBChannelCount: 0)
        default: MixerCapabilities(usbChannelCount: nil, nameableUSBChannelCount: Self.nameableUSBChannelCount)
        }
    }

    /// USB Channels 1–16 carry input channels 1–16 and 17–18 the aux return; any beyond are not the X-Air's.
    private static let nameableUSBChannelCount = 18

    /// USB Channels 1–16 carry input channels 1–16; 17–18 carry the aux return (left and right).
    /// The Mixer's actual USB routing is read in #20; until then this is the XR18's default.
    ///
    /// Mute, fader and input source are optional: if the Mixer doesn't answer the first of them,
    /// they're skipped for the rest rather than waiting out a timeout per query.
    public func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        var sources: [Source] = []
        guard usbChannelCount > 0 else { return sources }
        var readsMixState = true
        for usbChannel in 1...usbChannelCount {
            guard usbChannel <= Self.nameableUSBChannelCount else {
                sources.append(.fallback(usbChannel: usbChannel))
                continue
            }
            let isInput = usbChannel <= 16
            let base = isInput ? String(format: "/ch/%02d", usbChannel) : "/rtn/aux"
            let name = try await string(at: base + "/config/name")
            let color = MixerColor(xAirIndex: try await int(at: base + "/config/color"))
            var source = name.isEmpty ? .fallback(usbChannel: usbChannel, color: color) : Source(name: name, color: color)
            if readsMixState {
                do {
                    source.isMuted = try await optional { () async throws(MixerLinkProblem) in try await int(at: base + "/mix/on") == 0 }
                    source.fader = try await optional { () async throws(MixerLinkProblem) in try await float(at: base + "/mix/fader") }
                    if isInput {
                        source.inputSource = try await optional { () async throws(MixerLinkProblem) in Int(try await int(at: base + "/config/insrc")) }
                    }
                } catch {
                    // No reply: this Mixer doesn't report mix state. Stop asking.
                    readsMixState = false
                    source.isMuted = nil
                    source.fader = nil
                    source.inputSource = nil
                }
            }
            sources.append(source)
        }
        return sources
    }

    /// Reads an optional value: an odd reply makes it nil; no reply at all is thrown to the caller.
    private func optional<T>(_ read: () async throws(MixerLinkProblem) -> T) async throws(MixerLinkProblem) -> T? {
        do {
            return try await read()
        } catch .noReply(let host) {
            throw .noReply(host: host)
        } catch {
            return nil
        }
    }

    private func float(at address: String) async throws(MixerLinkProblem) -> Float {
        let reply = try await client.request(OSCMessage(address), timeout: timeout)
        guard case .float(let value)? = reply.arguments.first else { throw .other("\(address) didn't return a level") }
        return value
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

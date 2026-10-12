import OSC

/// The X-Air driver (XR12/XR16/XR18, MR18) over OSC on UDP port 10024.
public final class XAirDriver: MixerDriver {
    private let client: OSCUDPClient
    private let queries: MixerQueries

    public init(endpoint: MixerEndpoint, timeout: Duration = .seconds(1.5)) {
        client = OSCUDPClient(endpoint: endpoint)
        queries = MixerQueries(client: client, timeout: timeout)
    }

    /// `/xinfo` answers with the Mixer's IP, network name, model and firmware.
    public func identify() async throws(MixerLinkProblem) -> MixerIdentity {
        try await queries.identify()
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
    /// Mute, fader and input source are optional (see `MixerQueries.source`).
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
            let source = try await queries.source(at: base, usbChannel: usbChannel, inputSourceField: isInput ? "insrc" : nil, readsMixState: &readsMixState)
            sources.append(source)
        }
        return sources
    }

    /// /xremote makes the Mixer push changes to this sender for 10 seconds. It has no reply, so /xinfo
    /// is asked too, to know the Mixer is still there.
    public func renewLiveUpdates() async throws(MixerLinkProblem) {
        await client.send(OSCMessage("/xremote"))
        _ = try await identify()
    }

    /// Name and color changes pushed for input channels (USB Channels 1–16) and the aux return (17–18).
    public func sourceChanges() -> AsyncStream<SourceChange> {
        let messages = client.unsolicited
        return AsyncStream { continuation in
            let task = Task {
                for await message in messages {
                    for change in Self.changes(in: message) { continuation.yield(change) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func changes(in message: OSCMessage) -> [SourceChange] {
        let parts = message.address.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[2] == "config" else { return [] }
        let channels: [Int]
        switch (parts[0], parts[1]) {
        case ("ch", let number): channels = Int(number).flatMap { (1...16).contains($0) ? [$0] : nil } ?? []
        case ("rtn", "aux"): channels = [17, 18]
        default: channels = []
        }
        switch (parts[3], message.arguments.first) {
        case ("name", .string(let name)?): return channels.map { SourceChange(usbChannel: $0, name: name) }
        case ("color", .int(let index)?): return channels.map { SourceChange(usbChannel: $0, color: MixerColor(xAirIndex: index)) }
        default: return []
        }
    }
}

import OSC

/// The X32 driver (X32, X32 Compact, Producer and Rack; M32, M32R and M32C) over OSC on UDP port 10023 (#199).
public final class X32Driver: MixerDriver {
    private let client: OSCUDPClient
    private let queries: MixerQueries

    public init(endpoint: MixerEndpoint, timeout: Duration = .seconds(1.5)) {
        client = OSCUDPClient(endpoint: endpoint)
        queries = MixerQueries(client: client, timeout: timeout)
    }

    /// `/xinfo` answers as on the X-Air: the Mixer's IP, network name, model and firmware.
    public func identify() async throws(MixerLinkProblem) -> MixerIdentity {
        try await queries.identify()
    }

    /// An X-USB card sends 32 USB Channels, each nameable from one of the 32 input channels.
    public func capabilities(for identity: MixerIdentity) -> MixerCapabilities {
        MixerCapabilities(usbChannelCount: Self.channelCount, nameableUSBChannelCount: Self.channelCount)
    }

    /// USB Channel n carries input channel n: the X-USB card's default patch (card outs 1–32 from local inputs 1–32,
    /// each input on its own channel). The Mixer's actual routing is read in #20.
    ///
    /// Each channel's `config/source` is its input source. Mute, fader and input source are optional (see
    /// `MixerQueries.source`).
    public func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        var sources: [Source] = []
        guard usbChannelCount > 0 else { return sources }
        var readsMixState = true
        for usbChannel in 1...usbChannelCount {
            guard usbChannel <= Self.channelCount else {
                sources.append(.fallback(usbChannel: usbChannel))
                continue
            }
            let base = String(format: "/ch/%02d", usbChannel)
            sources.append(try await queries.source(at: base, usbChannel: usbChannel, inputSourceField: "source", readsMixState: &readsMixState))
        }
        return sources
    }

    /// Input channels, and USB Channels on an X-USB card.
    private static let channelCount = 32

    /// /xremote makes the X32 push changes to this sender for 10 seconds, as on the X-Air. It has no reply, so /xinfo
    /// is asked too, to know the Mixer is still there.
    public func renewLiveUpdates() async throws(MixerLinkProblem) {
        await client.send(OSCMessage("/xremote"))
        _ = try await identify()
    }

    /// Name and color changes pushed for input channels 1–32 (USB Channels 1–32).
    public func sourceChanges() -> AsyncStream<SourceChange> {
        let messages = client.unsolicited
        return AsyncStream { continuation in
            let task = Task {
                for await message in messages {
                    if let change = Self.change(in: message) { continuation.yield(change) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func change(in message: OSCMessage) -> SourceChange? {
        let parts = message.address.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "ch", parts[2] == "config",
              let usbChannel = Int(parts[1]), (1...channelCount).contains(usbChannel) else { return nil }
        switch (parts[3], message.arguments.first) {
        case ("name", .string(let name)?): return SourceChange(usbChannel: usbChannel, name: name)
        case ("color", .int(let index)?): return SourceChange(usbChannel: usbChannel, color: MixerColor(xAirIndex: index))
        default: return nil
        }
    }
}

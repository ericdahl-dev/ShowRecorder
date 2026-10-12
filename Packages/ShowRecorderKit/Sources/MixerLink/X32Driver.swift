import OSC
import Synchronization

/// The X32 driver (X32, X32 Compact, Producer and Rack; M32, M32R and M32C) over OSC on UDP port 10023 (#199).
public final class X32Driver: MixerDriver {
    let client: OSCUDPClient
    let queries: MixerQueries
    /// The routing and Sources last read, so pushed changes reach the right USB Channels.
    private let linked = Mutex<(routing: X32Routing?, sources: [Source])>((nil, []))

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

    /// Each USB Channel is named after the input channel actually on it, from the card routing, the input routing and
    /// each channel's source (#20, `X32Routing`). A USB Channel that carries no input channel, or every one when the
    /// Mixer doesn't answer its routing, gets its USB Channel name rather than a guess.
    ///
    /// Mute, fader and input source are optional (see `MixerQueries.source`).
    public func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        var sources: [Source] = []
        guard usbChannelCount > 0 else { return sources }
        let routing = await readRouting()
        var readsMixState = true
        for usbChannel in 1...usbChannelCount {
            guard usbChannel <= Self.channelCount, let channel = routing?.channel(forUSBChannel: usbChannel) else {
                sources.append(.fallback(usbChannel: usbChannel))
                continue
            }
            let base = String(format: "/ch/%02d", channel)
            sources.append(try await queries.source(at: base, usbChannel: usbChannel, inputSourceField: "source", readsMixState: &readsMixState))
        }
        linked.withLock { $0 = (routing, sources) }
        return sources
    }

    /// The card and input routing and every channel's source, or nil when the Mixer doesn't answer them or gives an
    /// odd reply. Older firmware may not know these addresses, which mustn't take the Link down: it just names no
    /// USB Channel. It stops at the first unanswered query, so that costs one timeout.
    private func readRouting() async -> X32Routing? {
        do {
            var card: [Int] = []
            var inputs: [Int] = []
            for block in ["1-8", "9-16", "17-24", "25-32"] {
                card.append(Int(try await queries.int(at: "/config/routing/CARD/" + block)))
                inputs.append(Int(try await queries.int(at: "/config/routing/IN/" + block)))
            }
            var channelSources: [Int] = []
            for channel in 1...Self.channelCount {
                channelSources.append(Int(try await queries.int(at: String(format: "/ch/%02d/config/source", channel))))
            }
            return X32Routing(cardBlocks: card, inputBlocks: inputs, channelSources: channelSources)
        } catch {
            return nil
        }
    }

    /// Input channels, and USB Channels on an X-USB card.
    private static let channelCount = 32

    /// /xremote makes the X32 push changes to this sender for 10 seconds, as on the X-Air. It has no reply, so /xinfo
    /// is asked too, to know the Mixer is still there.
    public func renewLiveUpdates() async throws(MixerLinkProblem) {
        await client.send(OSCMessage("/xremote"))
        _ = try await identify()
    }

    /// Name and color changes pushed for input channels, sent to every USB Channel that carries the channel. A change
    /// to the card or input routing, or to a channel's source, reads the Sources again and sends what moved.
    public func sourceChanges() -> AsyncStream<SourceChange> {
        let messages = client.unsolicited
        return AsyncStream { continuation in
            let task = Task {
                for await message in messages {
                    for change in await changes(after: message) { continuation.yield(change) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func changes(after message: OSCMessage) async -> [SourceChange] {
        let parts = message.address.split(separator: "/").map(String.init)
        if parts.count == 4, parts[0] == "config", parts[1] == "routing", parts[2] == "CARD" || parts[2] == "IN" {
            return await reread()
        }
        guard parts.count == 4, parts[0] == "ch", parts[2] == "config", let channel = Int(parts[1]) else { return [] }
        let usbChannels = linked.withLock { linked in
            linked.sources.indices.map { $0 + 1 }.filter { linked.routing?.channel(forUSBChannel: $0) == channel }
        }
        switch (parts[3], message.arguments.first) {
        case ("name", .string(let name)?): return usbChannels.map { SourceChange(usbChannel: $0, name: name) }
        case ("color", .int(let index)?): return usbChannels.map { SourceChange(usbChannel: $0, color: MixerColor(xAirIndex: index)) }
        case ("source", _): return await reread()
        default: return []
        }
    }

    /// Reads the Sources again after a routing change and says which USB Channels' names or colors moved.
    private func reread() async -> [SourceChange] {
        let before = linked.withLock { $0.sources }
        guard !before.isEmpty, let after = try? await sources(usbChannelCount: before.count) else { return [] }
        return zip(before, after).enumerated().compactMap { index, pair in
            let (old, new) = pair
            guard old.name != new.name || old.color != new.color else { return nil }
            return SourceChange(usbChannel: index + 1, name: old.name == new.name ? nil : (new.hasMixerName ? new.name : ""),
                                color: old.color == new.color ? nil : new.color)
        }
    }
}

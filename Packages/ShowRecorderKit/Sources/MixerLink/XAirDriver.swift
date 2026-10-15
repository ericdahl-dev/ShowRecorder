import OSC
import Synchronization

/// The X-Air driver (XR12/XR16/XR18, MR18) over OSC on UDP port 10024.
public final class XAirDriver: MixerDriver {
    let client: OSCUDPClient
    let queries: MixerQueries
    /// How long a fader set takes to land on the desk (`MixHoldDesk`): 80 ms, over the 60–70 ms measured on an XR18 (#688).
    let faderSettle: Duration
    /// What each USB Channel carries, and the Sources last read, so pushed changes reach the right USB Channels.
    /// Until the routing is read, the XR18's default.
    let linked = Mutex<(targets: [XAirRouting.Target?], sources: [Source])>((XAirDriver.defaultTargets, []))

    /// The XR18's default USB routing: USB 1-16 input channels 1-16, 17-18 the aux return.
    static let defaultTargets: [XAirRouting.Target?] = (1...16).map { .channel($0) } + [.auxReturn, .auxReturn]

    public init(endpoint: MixerEndpoint, timeout: Duration = .seconds(1.5), faderSettle: Duration = .milliseconds(80)) {
        client = OSCUDPClient(endpoint: endpoint)
        self.faderSettle = faderSettle
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

    /// Each USB Channel is named after what the Mixer routes to it (`/routing/usb/NN`, #20): an input channel, the aux
    /// return, or nothing nameable (FX, a bus, a send, the main mix), which keeps its USB Channel name. Firmware that
    /// doesn't answer the routing gets the XR18's default.
    ///
    /// Mute, fader and input source are optional (see `MixerQueries.source`).
    public func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        var sources: [Source] = []
        guard usbChannelCount > 0 else { return sources }
        let targets = await readTargets() ?? Self.defaultTargets
        var readsMixState = true
        for usbChannel in 1...usbChannelCount {
            guard usbChannel <= Self.nameableUSBChannelCount, let target = targets[usbChannel - 1] else {
                sources.append(.fallback(usbChannel: usbChannel))
                continue
            }
            var source: Source
            switch target {
            case .channel(let channel):
                source = try await queries.source(at: String(format: "/ch/%02d", channel), usbChannel: usbChannel, inputSourceField: "insrc", readsMixState: &readsMixState)
                source.routedFrom = "ch:\(channel)"
            case .auxReturn:
                source = try await queries.source(at: "/rtn/aux", usbChannel: usbChannel, inputSourceField: nil, readsMixState: &readsMixState)
                source.routedFrom = "aux"
            }
            sources.append(source)
        }
        linked.withLock { $0 = (targets, sources) }
        return sources
    }

    /// The USB routing, or nil when the Mixer doesn't answer it (older firmware). Stops at the first unanswered query.
    private func readTargets() async -> [XAirRouting.Target?]? {
        var targets: [XAirRouting.Target?] = []
        for usbChannel in 1...Self.nameableUSBChannelCount {
            guard let source = try? await queries.int(at: String(format: "/routing/usb/%02d", usbChannel)) else { return nil }
            targets.append(XAirRouting.target(ofSource: Int(source)))
        }
        return targets
    }

    /// /xremote makes the Mixer push changes to this sender for 10 seconds. It has no reply, so /xinfo
    /// is asked too, to know the Mixer is still there.
    public func renewLiveUpdates() async throws(MixerLinkProblem) {
        await client.send(OSCMessage("/xremote"))
        _ = try await identify()
    }

    /// Name and color changes pushed for input channels and the aux return, sent to every USB Channel that carries
    /// them. A pushed USB routing change reads the Sources again and sends what moved.
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
        if parts.count == 3, parts[0] == "routing", parts[1] == "usb" { return await reread() }
        guard parts.count == 4, parts[2] == "config" else { return [] }
        let target: XAirRouting.Target
        switch (parts[0], parts[1]) {
        case ("ch", let number):
            guard let channel = Int(number) else { return [] }
            target = .channel(channel)
        case ("rtn", "aux"): target = .auxReturn
        default: return []
        }
        let targets = linked.withLock { $0.targets }
        let usbChannels = targets.indices.filter { targets[$0] == target }.map { $0 + 1 }
        switch (parts[3], message.arguments.first) {
        case ("name", .string(let name)?): return usbChannels.map { SourceChange(usbChannel: $0, name: name) }
        case ("color", .int(let index)?): return usbChannels.map { SourceChange(usbChannel: $0, color: MixerColor(xAirIndex: index)) }
        default: return []
        }
    }

    /// Reads the Sources again after a routing change and says which USB Channels' names, colors or routing moved.
    private func reread() async -> [SourceChange] {
        let before = linked.withLock { $0.sources }
        guard !before.isEmpty, let after = try? await sources(usbChannelCount: before.count) else { return [] }
        return zip(before, after).enumerated().compactMap { index, pair in
            let (old, new) = pair
            guard old.name != new.name || old.color != new.color || old.routedFrom != new.routedFrom else { return nil }
            return SourceChange(usbChannel: index + 1, name: old.name == new.name ? nil : (new.hasMixerName ? new.name : ""),
                                color: old.color == new.color ? nil : new.color,
                                routedFrom: old.routedFrom == new.routedFrom ? nil : .some(new.routedFrom))
        }
    }
}

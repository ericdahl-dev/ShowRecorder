import Foundation
import Network
import OSC
import Synchronization

/// The WING driver (WING, WING Compact, WING Rack) (#417), from the WING Remote Protocols document (Maillot, V3.0.5-1,
/// firmware 3.0.5 and above). The WING is found with the plain-text knock `WING?` on UDP port 2222, which Maillot's
/// wingemul answers too; its parameters are read over OSC on UDP port 2223, which wingemul does not answer. Not yet
/// tried on a real WING. Offered only where `WingAvailability` allows.
///
/// Live updates come from re-reading every `rereadInterval`, never from an OSC subscription (`/*S`, `/*s`): a WING
/// keeps one subscriber, the last to ask, so subscribing would cut off any other OSC app on the desk (Eric, 2026-11-10).
public final class WingDriver: MixerDriver {
    let endpoint: MixerEndpoint
    let client: OSCUDPClient
    let timeout: Duration
    let rereadEvery: Duration

    /// How often the Sources are read again while the Link is up, at most; the Link's renewal (every 5 s) asks.
    public static let rereadInterval: Duration = .seconds(5)
    /// Queries one USB Channel's read takes at most: its output's group and input, then the Source's name and color.
    public static let queriesPerUSBChannel = 4
    /// Queries one read of all 48 USB Channels takes at most: 192, about 20 KB each way.
    public static var queriesPerRead: Int { usbChannelCount * queriesPerUSBChannel }

    /// What the Link was last told, and whether a re-read is running.
    private struct Live {
        var sources: [Source] = []
        var lastRead: ContinuousClock.Instant?
        var rereading = false
        var listeners: [UUID: AsyncStream<SourceChange>.Continuation] = [:]
    }

    private let live = Mutex(Live())

    /// `endpoint` is where the WING answers the knock (port 2222); `oscPort` is its OSC port on the same host.
    public init(endpoint: MixerEndpoint, oscPort: UInt16 = 2223, timeout: Duration = .seconds(1.5),
                rereadEvery: Duration = WingDriver.rereadInterval) {
        self.endpoint = endpoint
        client = OSCUDPClient(endpoint: MixerEndpoint(host: endpoint.host, port: oscPort))
        self.timeout = timeout
        self.rereadEvery = rereadEvery
    }

    deinit {
        live.withLock { $0.listeners.values.forEach { $0.finish() } }
    }

    /// The knock's reply: "WING,<ip>,<name>,<model>,<serial>,<firmware>". The IP in it is ignored (wingemul sends 0.0.0.0).
    public func identify() async throws(MixerLinkProblem) -> MixerIdentity {
        let reply = try await TextRequest.ask(MixerProbe.wing.request, at: endpoint, timeout: timeout)
        guard let identity = MixerProbe.wing.identity(reply) else { throw .other("The WING's reply to WING? was incomplete") }
        return identity
    }

    /// All three models have a 48-in, 48-out USB audio interface built in, each output nameable from its routing.
    public func capabilities(for identity: MixerIdentity) -> MixerCapabilities {
        MixerCapabilities(usbChannelCount: Self.usbChannelCount, nameableUSBChannelCount: Self.usbChannelCount)
    }

    static let usbChannelCount = 48

    /// Each USB Channel is named and colored after the Source its USB output carries: `/io/out/USB/n/grp` and `/in`
    /// give the Source's group and number, and `/io/in/<grp>/<in>/name` and `/col` its name and color. On a WING a
    /// Source keeps its name wherever it is patched, so this is the name the operator gave the signal. A USB output
    /// patched to nothing or to a mix (a bus, main, matrix, FX send or monitor) keeps its USB Channel name. A WING that
    /// doesn't answer (wingemul answers no OSC) names nothing: reading stops at the first unanswered query, which
    /// costs one timeout.
    public func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        guard usbChannelCount > 0 else { return [] }
        let sources = (try? await read(usbChannelCount: usbChannelCount))
            ?? (1...usbChannelCount).map { Source.fallback(usbChannel: $0) }
        live.withLock {
            $0.sources = sources
            $0.lastRead = .now
        }
        return sources
    }

    /// Every USB Channel's Source, or a throw at the first query the WING doesn't answer.
    private func read(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        var sources: [Source] = []
        for usbChannel in 1...usbChannelCount {
            sources.append(try await source(usbChannel: usbChannel))
        }
        return sources
    }

    /// Source groups a USB output can carry that have a name and color of their own (local, aux, AES50 A to C,
    /// StageConnect, USB, card, module, USB player, AES/EBU, user signals and the oscillator).
    static let sourceGroups: Set<String> = ["LCL", "AUX", "A", "B", "C", "SC", "USB", "CRD", "MOD", "PLAY", "AES", "USR", "OSC"]

    private func source(usbChannel: Int) async throws(MixerLinkProblem) -> Source {
        let group = try await string(at: "/io/out/USB/\(usbChannel)/grp")
        let input = try await int(at: "/io/out/USB/\(usbChannel)/in")
        guard Self.sourceGroups.contains(group), usbChannel <= Self.usbChannelCount else { return .fallback(usbChannel: usbChannel) }
        let base = "/io/in/\(group)/\(input)"
        let name = try await string(at: base + "/name")
        let color = MixerColor(wingIndex: try await int(at: base + "/col"))
        var source = name.isEmpty ? Source.fallback(usbChannel: usbChannel, color: color) : Source(name: name, color: color)
        source.routedFrom = "\(group):\(input)"
        return source
    }

    /// A string or enum parameter: the WING answers ",s" with its text.
    private func string(at address: String) async throws(MixerLinkProblem) -> String {
        let reply = try await client.request(OSCMessage(address), timeout: timeout)
        guard case .string(let value)? = reply.arguments.first else { throw .other("\(address) didn't return text") }
        return value
    }

    /// An integer parameter: the WING answers ",sfi", its text, its raw 0…1 value and the integer.
    private func int(at address: String) async throws(MixerLinkProblem) -> Int {
        let reply = try await client.request(OSCMessage(address), timeout: timeout)
        for argument in reply.arguments.reversed() { if case .int(let value) = argument { return Int(value) } }
        if case .string(let text)? = reply.arguments.first, let value = Int(text) { return value }
        throw .other("\(address) didn't return a number")
    }

    /// Checks that the WING still answers, then starts a re-read when the last read is `rereadEvery` old and none is
    /// running. The re-read runs on its own, so a slow WING never holds up the renewal.
    public func renewLiveUpdates() async throws(MixerLinkProblem) {
        _ = try await identify()
        let count: Int? = live.withLock { live in
            guard !live.rereading, !live.sources.isEmpty,
                  live.lastRead.map({ ContinuousClock.now - $0 >= rereadEvery }) ?? true else { return nil }
            live.rereading = true
            return live.sources.count
        }
        guard let count else { return }
        Task { await reread(usbChannelCount: count) }
    }

    /// Reads the Sources again and sends what moved: a rename, a recolor or a re-patch. A read the WING doesn't
    /// finish sends nothing, so a WING that goes quiet doesn't rename everything to "USB 01".
    private func reread(usbChannelCount: Int) async {
        let after = try? await read(usbChannelCount: usbChannelCount)
        let (changes, listeners) = live.withLock { live -> ([SourceChange], [AsyncStream<SourceChange>.Continuation]) in
            live.rereading = false
            live.lastRead = .now
            guard let after, after.count == live.sources.count else { return ([], []) }
            let changes = Self.changes(from: live.sources, to: after)
            live.sources = after
            return (changes, Array(live.listeners.values))
        }
        for change in changes { listeners.forEach { $0.yield(change) } }
    }

    /// What moved between two reads, as the X32 driver reports a re-read.
    static func changes(from before: [Source], to after: [Source]) -> [SourceChange] {
        zip(before, after).enumerated().compactMap { index, pair in
            let (old, new) = pair
            guard old.name != new.name || old.color != new.color || old.routedFrom != new.routedFrom else { return nil }
            return SourceChange(usbChannel: index + 1, name: old.name == new.name ? nil : (new.hasMixerName ? new.name : ""),
                                color: old.color == new.color ? nil : new.color,
                                routedFrom: old.routedFrom == new.routedFrom ? nil : .some(new.routedFrom))
        }
    }

    public func sourceChanges() -> AsyncStream<SourceChange> {
        let (stream, continuation) = AsyncStream<SourceChange>.makeStream()
        let id = UUID()
        live.withLock { $0.listeners[id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.live.withLock { _ = $0.listeners.removeValue(forKey: id) } }
        return stream
    }
}

/// One plain UDP datagram out and the first one back, for a family whose knock isn't OSC (the WING's `WING?`).
enum TextRequest {
    static func ask(_ request: [UInt8], at endpoint: MixerEndpoint, timeout: Duration) async throws(MixerLinkProblem) -> [UInt8] {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else { throw .invalidAddress(endpoint.host) }
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .udp)
        defer { connection.cancel() }
        let waiting = Mutex<CheckedContinuation<[UInt8]?, Never>?>(nil)
        let finish: @Sendable ([UInt8]?) -> Void = { reply in
            waiting.withLock { $0.take() }?.resume(returning: reply)
        }
        let reply = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[UInt8]?, Never>) in
                waiting.withLock { $0 = continuation }
                connection.receiveMessage { data, _, _, _ in finish(data.map { Array($0) }) }
                connection.start(queue: .global(qos: .userInitiated))
                connection.send(content: Data(request), completion: .contentProcessed { _ in })
                Task {
                    try? await Task.sleep(for: timeout)
                    finish(nil)
                }
            }
        } onCancel: {
            finish(nil)
        }
        guard let reply else { throw .noReply(host: endpoint.host) }
        return reply
    }
}

extension MixerColor {
    /// A WING color, 1 to 12, as the nearest of the eight hues. The WING's palette names, in order, are thought to be
    /// gray blue, medium blue, dark blue, turquoise, green, olive green, yellow, orange, red, coral, pink and mauve; that
    /// order is not confirmed from a WING or its documentation (#417). Anything else is off.
    public init(wingIndex index: Int) {
        let hue: Hue = switch index {
        case 1...3: .blue
        case 4: .cyan
        case 5...6: .green
        case 7...8: .yellow
        case 9...10: .red
        case 11...12: .magenta
        default: .off
        }
        self.init(hue: hue, inverted: false)
    }
}

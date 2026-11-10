import Foundation
import Network
import OSC
import Synchronization

/// The WING driver (WING, WING Compact, WING Rack) (#417), from the WING Remote Protocols document (Maillot, V3.0.5-1,
/// firmware 3.0.5 and above). The WING is found with the plain-text knock `WING?` on UDP port 2222, which Maillot's
/// wingemul answers too; its parameters are read over OSC on UDP port 2223, which wingemul does not answer. Not yet
/// tried on a real WING. Offered only where `WingAvailability` allows.
public final class WingDriver: MixerDriver {
    let endpoint: MixerEndpoint
    let client: OSCUDPClient
    let timeout: Duration

    /// `endpoint` is where the WING answers the knock (port 2222); `oscPort` is its OSC port on the same host.
    public init(endpoint: MixerEndpoint, oscPort: UInt16 = 2223, timeout: Duration = .seconds(1.5)) {
        self.endpoint = endpoint
        client = OSCUDPClient(endpoint: MixerEndpoint(host: endpoint.host, port: oscPort))
        self.timeout = timeout
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
        var sources: [Source] = []
        do {
            for usbChannel in 1...usbChannelCount {
                sources.append(try await source(usbChannel: usbChannel))
            }
        } catch {
            return (1...usbChannelCount).map { Source.fallback(usbChannel: $0) }
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

    /// Checks that the WING still answers.
    public func renewLiveUpdates() async throws(MixerLinkProblem) {
        _ = try await identify()
    }

    public func sourceChanges() -> AsyncStream<SourceChange> {
        AsyncStream { $0.finish() }
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

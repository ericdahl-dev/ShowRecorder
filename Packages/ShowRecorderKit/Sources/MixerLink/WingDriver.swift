import Foundation
import Network
import OSC
import Synchronization

/// The WING driver (WING, WING Compact, WING Rack) (#417), from the WING Remote Protocols document (Maillot, V3.0.5-1,
/// firmware 3.0.5 and above). The WING is found with the plain-text knock `WING?` on UDP port 2222, which Maillot's
/// wingemul answers too; its parameters are read over OSC on UDP port 2223, which wingemul does not answer. Not yet
/// tried on a real WING. Offered only where `WingAvailability` allows. This first step identifies the WING; every USB
/// Channel keeps its USB Channel name.
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

    /// All three models have a 48-in, 48-out USB audio interface built in. None is named yet.
    public func capabilities(for identity: MixerIdentity) -> MixerCapabilities {
        MixerCapabilities(usbChannelCount: Self.usbChannelCount, nameableUSBChannelCount: 0)
    }

    static let usbChannelCount = 48

    public func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        guard usbChannelCount > 0 else { return [] }
        return (1...usbChannelCount).map { Source.fallback(usbChannel: $0) }
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

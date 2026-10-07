import Foundation
import Network
import OSC

/// Sends OSC queries over UDP and matches replies to them by address.
actor OSCUDPClient {
    private struct Pending {
        let id: UUID
        let address: String
        let continuation: CheckedContinuation<OSCMessage, any Error>
    }

    private let endpoint: MixerEndpoint
    private let connection: NWConnection
    private var started = false
    private var pending: [Pending] = []
    /// Set when the connection reports a problem; pending and new requests fail with it.
    private var problem: MixerLinkProblem?

    init(endpoint: MixerEndpoint) {
        self.endpoint = endpoint
        connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.port) ?? 10024,
            using: .udp)
    }

    deinit { connection.cancel() }

    /// Sends `message` and waits for the first reply with `replyAddress` (by default the same address).
    func request(_ message: OSCMessage, replyAddress: String? = nil, timeout: Duration) async throws(MixerLinkProblem) -> OSCMessage {
        startIfNeeded()
        if let problem { throw problem }
        let id = UUID()
        do {
            return try await withCheckedThrowingContinuation { continuation in
                pending.append(Pending(id: id, address: replyAddress ?? message.address, continuation: continuation))
                connection.send(content: Data(message.encoded()), completion: .contentProcessed { [weak self] error in
                    guard let error, let self else { return }
                    Task { await self.fail(id, with: MixerLinkProblem(error, path: nil, host: self.endpoint.host)) }
                })
                Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    await self?.fail(id, with: .noReply(host: self?.endpoint.host ?? ""))
                }
            }
        } catch let problem as MixerLinkProblem {
            throw problem
        } catch {
            throw .other(String(describing: error))
        }
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .waiting(let error), .failed(let error):
                let path = self.connection.currentPath
                Task { await self.connectionFailed(MixerLinkProblem(error, path: path, host: self.endpoint.host)) }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receive()
    }

    private nonisolated func receive() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let packet = try? OSCPacket(decoding: Array(data)) {
                Task { await self.deliver(packet.messages) }
            }
            if error == nil { self.receive() }
        }
    }

    private func deliver(_ messages: [OSCMessage]) {
        for message in messages {
            guard let index = pending.firstIndex(where: { $0.address == message.address }) else { continue }
            pending.remove(at: index).continuation.resume(returning: message)
        }
    }

    private func fail(_ id: UUID, with problem: MixerLinkProblem) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index).continuation.resume(throwing: problem)
    }

    private func connectionFailed(_ problem: MixerLinkProblem) {
        self.problem = problem
        let failed = pending
        pending.removeAll()
        for request in failed { request.continuation.resume(throwing: problem) }
    }
}

extension MixerLinkProblem {
    /// Maps a Network.framework error (and the path, when known) to something an operator can act on.
    init(_ error: NWError, path: NWPath?, host: String) {
        if path?.unsatisfiedReason == .localNetworkDenied {
            self = .localNetworkDenied
            return
        }
        switch error {
        case .posix(.ENETUNREACH), .posix(.EHOSTUNREACH), .posix(.ENETDOWN), .posix(.EHOSTDOWN):
            self = .networkUnreachable
        case .posix(.ECONNREFUSED):  // the host is there but nothing listens on the port
            self = .noReply(host: host)
        case .dns(-65570):  // kDNSServiceErr_PolicyDenied: local network access refused
            self = .localNetworkDenied
        default:
            self = .other(error.localizedDescription)
        }
    }
}

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
    private var connection: NWConnection
    private var started = false
    /// Set when the connection failed for good or stopped receiving. The next send or request opens a new one, so
    /// the Link can come back by itself after a Mixer power cycle or a network change (#321). The renewal loop sends
    /// every few seconds, which paces the rebuilds.
    private var needsRebuild = false
    /// Which connection a state change or receive error came from; one from a replaced connection is ignored.
    private var generation = 0
    private var pending: [Pending] = []
    /// Set when the connection reports a problem; pending and new requests fail with it.
    private var problem: MixerLinkProblem?
    /// Messages nobody asked for, such as the changes a Mixer pushes after /xremote.
    nonisolated let unsolicited: AsyncStream<OSCMessage>
    private let unsolicitedContinuation: AsyncStream<OSCMessage>.Continuation

    init(endpoint: MixerEndpoint) {
        self.endpoint = endpoint
        (unsolicited, unsolicitedContinuation) = AsyncStream.makeStream()
        connection = Self.makeConnection(to: endpoint)
    }

    private static func makeConnection(to endpoint: MixerEndpoint) -> NWConnection {
        NWConnection(host: NWEndpoint.Host(endpoint.host), port: NWEndpoint.Port(rawValue: endpoint.port) ?? 10024, using: .udp)
    }

    deinit {
        unsolicitedContinuation.finish()
        connection.cancel()
    }

    /// Sends `message` without waiting for a reply.
    func send(_ message: OSCMessage) {
        startIfNeeded()
        connection.send(content: Data(message.encoded()), completion: .contentProcessed { _ in })
    }

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
        if needsRebuild { rebuild() }
        guard !started else { return }
        started = true
        let connection = connection, generation = generation
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .waiting(let error):
                // Waiting recovers by itself (the network comes back); fail requests meanwhile.
                let problem = MixerLinkProblem(error, path: connection.currentPath, host: self.endpoint.host)
                Task { await self.connectionWaiting(problem, generation: generation) }
            case .failed(let error):
                Task { await self.connectionFailed(error, path: connection.currentPath, generation: generation) }
            case .ready:
                Task { await self.connectionReady(generation: generation) }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        receive(on: connection, generation: generation)
    }

    private nonisolated func receive(on connection: NWConnection, generation: Int) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let packet = try? OSCPacket(decoding: Array(data)) {
                Task { await self.deliver(packet.messages) }
            }
            if error == nil {
                self.receive(on: connection, generation: generation)
            } else {
                Task { await self.receiveFailed(generation: generation) }
            }
        }
    }

    /// Replaces the connection with a new one to the same Mixer.
    private func rebuild() {
        connection.stateUpdateHandler = nil
        connection.cancel()
        connection = Self.makeConnection(to: endpoint)
        generation += 1
        started = false
        needsRebuild = false
        problem = nil
    }

    private func deliver(_ messages: [OSCMessage]) {
        for message in messages {
            guard let index = pending.firstIndex(where: { $0.address == message.address }) else {
                unsolicitedContinuation.yield(message)
                continue
            }
            pending.remove(at: index).continuation.resume(returning: message)
        }
    }

    private func fail(_ id: UUID, with problem: MixerLinkProblem) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index).continuation.resume(throwing: problem)
    }

    /// The network came back: stop failing requests with the problem it had.
    private func connectionReady(generation: Int) {
        guard generation == self.generation else { return }
        problem = nil
    }

    private func connectionWaiting(_ problem: MixerLinkProblem, generation: Int) {
        guard generation == self.generation else { return }
        failPending(with: problem)
    }

    /// The connection failed for good. Pending requests fail with the problem; the next one opens a new connection.
    func connectionFailed(_ error: NWError, path: NWPath? = nil, generation: Int? = nil) {
        guard generation ?? self.generation == self.generation else { return }
        failPending(with: MixerLinkProblem(error, path: path, host: endpoint.host))
        needsRebuild = true
    }

    /// The connection stopped receiving. Nothing more would arrive on it, so the next request opens a new one.
    func receiveFailed(generation: Int? = nil) {
        guard generation ?? self.generation == self.generation else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        needsRebuild = true
    }

    private func failPending(with problem: MixerLinkProblem) {
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

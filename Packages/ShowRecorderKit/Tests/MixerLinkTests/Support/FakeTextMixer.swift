import Foundation
import Network
import Synchronization

/// A loopback Mixer that answers one plain-text request with one plain-text reply, the way a family that doesn't
/// speak `/xinfo` is probed (#442). It records every datagram it is sent.
final class FakeTextMixer: Sendable {
    private let listener: NWListener
    private final class Log: Sendable {
        let requests = Mutex<[String]>([])
    }

    private let log = Log()
    let port: UInt16

    var requests: [String] { log.requests.withLock { $0 } }

    init(answering request: String, with reply: String) async throws {
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = AsyncStream<UInt16>.makeStream()
        listener.stateUpdateHandler = { [listener] update in
            if case .ready = update, let port = listener.port?.rawValue { ready.continuation.yield(port) }
        }
        let log = log
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            @Sendable func serve() {
                connection.receiveMessage { data, _, _, error in
                    guard error == nil, let data else { return }
                    let text = String(decoding: data, as: UTF8.self)
                    log.requests.withLock { $0.append(text) }
                    if text == request { connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in }) }
                    serve()
                }
            }
            serve()
        }
        listener.start(queue: .global())
        var iterator = ready.stream.makeAsyncIterator()
        self.listener = listener
        self.port = await iterator.next() ?? 0
    }

    deinit { listener.cancel() }
}

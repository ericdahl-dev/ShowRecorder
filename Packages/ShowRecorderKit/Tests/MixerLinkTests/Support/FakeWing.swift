import Foundation
import Network
import OSC
import Synchronization

/// A fake Behringer WING (#417): answers OSC queries on a loopback UDP port the way the WING Remote Protocols document
/// (Maillot, V3.0.5-1) shows the console answering on port 2223. `/?` gets the console's identity string; any other
/// address it knows gets its reply arguments; anything else goes unanswered. Written from the document only: no
/// emulator or real WING was used.
final class FakeWing: Sendable {
    struct State: Sendable {
        /// The `/?` reply: "WING,<ip>,<name>,<model>,<serial>,<firmware>".
        var identity = "WING,127.0.0.1,FOH-WING,ngc-full,S1234,3.1.0"
        /// Reply arguments by address, as the console sends them.
        var replies: [String: [OSCArgument]] = [:]
        /// Every address queried, in order.
        var queries: [String] = []
    }

    private let listener: NWListener
    private let state: Mutex<State>
    let port: UInt16

    init(_ initial: State = State()) async throws {
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = AsyncStream<UInt16>.makeStream()
        listener.stateUpdateHandler = { [listener] update in
            switch update {
            case .ready: if let port = listener.port?.rawValue { ready.continuation.yield(port) }
            case .failed: ready.continuation.finish()
            default: break
            }
        }
        let state = Mutex(initial)
        self.state = state
        listener.newConnectionHandler = { [state] connection in
            connection.start(queue: .global())
            @Sendable func serve() {
                connection.receiveMessage { data, _, _, error in
                    guard error == nil, let data, let message = try? OSCMessage(decoding: Array(data)) else { return }
                    let reply: OSCMessage? = state.withLock { state in
                        state.queries.append(message.address)
                        if message.address == "/?" { return OSCMessage("/?", [.string(state.identity)]) }
                        return state.replies[message.address].map { OSCMessage(message.address, $0) }
                    }
                    if let reply { connection.send(content: Data(reply.encoded()), completion: .contentProcessed { _ in }) }
                    serve()
                }
            }
            serve()
        }
        listener.start(queue: .global())
        self.listener = listener
        var iterator = ready.stream.makeAsyncIterator()
        guard let port = await iterator.next() else { throw CancellationError() }
        self.port = port
    }

    deinit { listener.cancel() }

    var queries: [String] { state.withLock { $0.queries } }
}

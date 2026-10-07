import Foundation
import Network
import OSC
import Synchronization

/// A fake X-Air mixer: answers OSC queries on a loopback UDP port from in-memory state.
final class FakeXAirMixer: Sendable {
    struct Channel: Sendable {
        var name: String
        var color: Int32
    }

    struct State: Sendable {
        var networkName = "FOH-XR18"
        var model = "XR18"
        var firmware = "1.22"
        var channels: [Channel] = (1...16).map { _ in Channel(name: "", color: 0) }
        var auxReturn = Channel(name: "", color: 0)
        /// When false, the mixer receives queries but never answers.
        var answers = true
        /// Every address queried, in order.
        var queries: [String] = []
    }

    private let responder: Responder
    private let listener: NWListener
    let port: UInt16

    init(_ state: State = State()) async throws {
        let responder = Responder(state)
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = AsyncStream<UInt16>.makeStream()
        listener.stateUpdateHandler = { [listener] update in
            if case .ready = update, let port = listener.port?.rawValue { ready.continuation.yield(port) }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            responder.serve(connection)
        }
        listener.start(queue: .global())
        var iterator = ready.stream.makeAsyncIterator()
        self.responder = responder
        self.listener = listener
        port = await iterator.next() ?? 0
    }

    deinit { listener.cancel() }

    func update(_ change: @Sendable (inout State) -> Void) { responder.state.withLock { change(&$0) } }

    var queries: [String] { responder.state.withLock { $0.queries } }

    private final class Responder: Sendable {
        let state: Mutex<State>

        init(_ state: State) { self.state = Mutex(state) }

        func serve(_ connection: NWConnection) {
            connection.receiveMessage { [self] data, _, _, error in
                guard error == nil else { return }
                if let data, let query = try? OSCMessage(decoding: Array(data)), let reply = reply(to: query) {
                    connection.send(content: Data(reply.encoded()), completion: .contentProcessed { _ in })
                }
                serve(connection)
            }
        }

        private func reply(to query: OSCMessage) -> OSCMessage? {
            state.withLock { state in
                state.queries.append(query.address)
                guard state.answers else { return nil }
                let parts = query.address.split(separator: "/").map(String.init)
                switch parts {
                case ["xinfo"]:
                    return OSCMessage("/xinfo", ["127.0.0.1", .string(state.networkName), .string(state.model), .string(state.firmware)])
                case let p where p.count == 4 && p[0] == "ch" && p[2] == "config":
                    guard let number = Int(p[1]), (1...16).contains(number) else { return nil }
                    let channel = state.channels[number - 1]
                    return p[3] == "name" ? OSCMessage(query.address, [.string(channel.name)])
                        : p[3] == "color" ? OSCMessage(query.address, [.int(channel.color)]) : nil
                case ["rtn", "aux", "config", "name"]:
                    return OSCMessage(query.address, [.string(state.auxReturn.name)])
                case ["rtn", "aux", "config", "color"]:
                    return OSCMessage(query.address, [.int(state.auxReturn.color)])
                default:
                    return nil
                }
            }
        }
    }
}

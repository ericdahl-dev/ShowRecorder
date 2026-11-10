import Foundation
import Network
import OSC
import Synchronization

/// A fake Behringer WING (#417), from the WING Remote Protocols document (Maillot, V3.0.5-1): on one loopback UDP port
/// it answers the discovery knock `WING?` (port 2222 on a real WING), on another it answers OSC queries (port 2223).
/// `/?` gets the console's identity text; any other address it knows gets its reply arguments; anything else goes
/// unanswered. Written from the document and from what Patrick Maillot's wingemul answers to the knock; no real WING.
final class FakeWing: Sendable {
    struct State: Sendable {
        /// The identity text: "WING,<ip>,<name>,<model>,<serial>,<firmware>". wingemul sends 0.0.0.0 as its IP.
        var identity = "WING,0.0.0.0,FOH-WING,ngc-full,S1234,3.1.1"
        /// OSC reply arguments by address, as the console sends them.
        var replies: [String: [OSCArgument]] = [:]
        /// Every knock and OSC address received, in order.
        var queries: [String] = []
        /// When false, the OSC port takes queries but never answers, as wingemul does.
        var answersOSC = true
    }

    /// The state, in a class so the listeners' handlers can share it (a `Mutex` can't be captured).
    private final class Box: Sendable {
        let state: Mutex<State>
        /// The OSC replies held back, or nil while replies go out at once. One lock, so none is lost on release.
        let held = Mutex<[@Sendable () -> Void]?>(nil)
        init(_ state: State) { self.state = Mutex(state) }

        /// Sends now, or keeps the send for `releaseReplies()` while replies are held.
        func deliver(_ send: @escaping @Sendable () -> Void) {
            let sendNow = held.withLock { held -> Bool in
                guard held != nil else { return true }
                held?.append(send)
                return false
            }
            if sendNow { send() }
        }
    }

    private let listeners: [NWListener]
    private let box: Box
    /// The discovery port (2222 on a real WING).
    let port: UInt16
    /// The OSC port (2223 on a real WING).
    let oscPort: UInt16

    init(_ initial: State = State()) async throws {
        let box = Box(initial)
        self.box = box
        let (knock, port) = try await Self.listen { data in
            let text = String(decoding: data, as: UTF8.self)
            return box.state.withLock { state in
                state.queries.append(text)
                return text == "WING?" ? Data(state.identity.utf8) : nil
            }
        }
        let (osc, oscPort) = try await Self.listen(deliver: { box.deliver($0) }) { data in
            guard let message = try? OSCMessage(decoding: Array(data)) else { return nil }
            let reply: OSCMessage? = box.state.withLock { state in
                state.queries.append(message.address)
                guard state.answersOSC else { return nil }
                if message.address == "/?" { return OSCMessage("/?", [.string(state.identity)]) }
                return state.replies[message.address].map { OSCMessage(message.address, $0) }
            }
            return reply.map { Data($0.encoded()) }
        }
        listeners = [knock, osc]
        self.port = port
        self.oscPort = oscPort
    }

    deinit { listeners.forEach { $0.cancel() } }

    var queries: [String] { box.state.withLock { $0.queries } }

    /// How the WING answers a query of an integer parameter: ",sfi", its text, its raw 0…1 value and the integer.
    static func intReply(_ value: Int) -> [OSCArgument] { [.string(String(value)), .float(0), .int(Int32(value))] }

    func update(_ change: @Sendable (inout State) -> Void) { box.state.withLock { change(&$0) } }

    /// Holds back every OSC reply from now until `releaseReplies()`.
    func holdReplies() { box.held.withLock { $0 = $0 ?? [] } }

    /// Sends the held replies and answers at once again.
    func releaseReplies() {
        let sends = box.held.withLock { held in defer { held = nil }; return held ?? [] }
        sends.forEach { $0() }
    }

    /// Renames Source `path` ("LCL/1") at the desk. The WING pushes nothing here: the driver finds it by re-reading.
    func rename(source path: String, to name: String) {
        update { $0.replies["/io/in/\(path)/name"] = [.string(name)] }
    }

    /// Recolors Source `path` ("LCL/1") at the desk.
    func recolor(source path: String, to color: Int) {
        update { $0.replies["/io/in/\(path)/col"] = FakeWing.intReply(color) }
    }

    /// Re-patches USB output `usb` to `group` and `input` at the desk.
    func repatch(usb: Int, to group: String, _ input: Int) {
        update {
            $0.replies["/io/out/USB/\(usb)/grp"] = [.string(group)]
            $0.replies["/io/out/USB/\(usb)/in"] = FakeWing.intReply(input)
        }
    }

    /// A loopback UDP listener that answers each datagram with `answer`'s reply, if any.
    private static func listen(
        deliver: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { $0() }, answer: @escaping @Sendable (Data) -> Data?
    ) async throws -> (NWListener, UInt16) {
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
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            @Sendable func serve() {
                connection.receiveMessage { data, _, _, error in
                    guard error == nil, let data else { return }
                    if let reply = answer(data) {
                        deliver { connection.send(content: reply, completion: .contentProcessed { _ in }) }
                    }
                    serve()
                }
            }
            serve()
        }
        listener.start(queue: .global())
        var iterator = ready.stream.makeAsyncIterator()
        guard let port = await iterator.next() else { throw CancellationError() }
        return (listener, port)
    }
}

import Foundation
import Network
import OSC
import Synchronization

/// A fake X-Air mixer: answers OSC queries on a loopback UDP port from in-memory state. `State.x32()` makes it an
/// X32 instead: 32 input channels, each with `config/source` in place of the X-Air's `config/insrc`, and no aux return.
final class FakeXAirMixer: Sendable {
    struct Channel: Sendable {
        var name: String
        var color: Int32
        /// X-Air "on": 1 = unmuted, 0 = muted.
        var on: Int32 = 1
        var fader: Float = 0.75
        var inputSource: Int32 = 0
        /// X32 Re-Gain settings, as OSC floats (0…1) and ints.
        var gateThreshold: Float = 0.5
        var compressorThreshold: Float = 0.5
        var monoLevel: Float = 0
        var sendLevels: [Float] = Array(repeating: 0, count: 16)
        /// One per odd send (1, 3 … 15): 0–3 pre-fader (IN/LC, <-EQ, EQ->, PRE), 4 POST, 5 GRP.
        var sendTypes: [Int32] = Array(repeating: 4, count: 8)
        var gateKey: Int32 = 0
        var compressorKey: Int32 = 0
    }

    struct State: Sendable {
        var networkName = "FOH-XR18"
        var model = "XR18"
        var firmware = "1.22"
        var channels: [Channel] = (1...16).map { _ in Channel(name: "", color: 0) }
        var auxReturn = Channel(name: "", color: 0)
        /// When false, the mixer receives queries but never answers.
        var answers = true
        /// When false, mute, fader and input source queries go unanswered (older firmware, say).
        var answersMixState = true
        /// When true, faders are reported as integers instead of floats.
        var reportsFaderAsInt = false
        /// How long a /xremote keeps the sender subscribed to pushed changes. A real X-Air: 10 seconds.
        var xremoteLifetime: TimeInterval = 10
        /// Every address queried, in order.
        var queries: [String] = []
        /// The input-source field of an input channel: the X-Air's "insrc", the X32's "source".
        var inputSourceField = "insrc"
        /// Whether `/rtn/aux` answers (the X-Air's aux return; the X32 has none).
        var hasAuxReturn = true
        /// X32 only: `/config/routing/CARD/…` and `/config/routing/IN/…`, one number per block of 8 (nil: no answer).
        var cardBlocks: [Int32]?
        var inputBlocks: [Int32]?
        /// X32 only: `/-ha/NN/index`, the preamp behind each channel (-1: none). Default: channel n on preamp n-1.
        var headampOfChannel: [Int32] = Array(0..<32)
        /// X32 only: `/headamp/NNN/gain` as OSC floats.
        var headampGains: [Float] = Array(repeating: 0, count: 128)
        /// Every value set (an address with one argument), in order, so tests can see what the driver wrote.
        var writes: [(address: String, value: OSCArgument)] = []
        /// Values set by a client: a later query of that address answers with it.
        var set: [String: OSCArgument] = [:]

        /// An X32 (or, with another `model`, an M32) as Maillot's X32 emulator answers it.
        static func x32(model: String = "X32") -> State {
            var state = State()
            state.networkName = "FOH-X32"
            state.model = model
            state.firmware = "4.06"
            // A real X32's defaults: channel n on In n, and the card and inputs on AN1-8 … AN25-32.
            state.channels = (1...32).map { Channel(name: "", color: 0, inputSource: Int32($0)) }
            state.inputSourceField = "source"
            state.hasAuxReturn = false
            state.cardBlocks = [0, 1, 2, 3]
            state.inputBlocks = [0, 1, 2, 3]
            return state
        }
    }

    private let responder: Responder
    private let listener: Mutex<NWListener?>
    let port: UInt16

    init(_ state: State = State()) async throws {
        let responder = Responder(state)
        let (listener, port) = try await Self.listen(on: .any, responder: responder)
        self.responder = responder
        self.listener = Mutex(listener)
        self.port = port
    }

    deinit { listener.withLock { $0?.cancel() } }

    /// Opens a loopback UDP listener on `port` that answers with `responder`, and returns it with its port.
    private static func listen(on port: NWEndpoint.Port, responder: Responder) async throws -> (NWListener, UInt16) {
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        parameters.allowLocalEndpointReuse = true
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
        return (listener, await iterator.next() ?? 0)
    }

    /// Switches the Mixer off, as a power cycle does: nothing listens on its port any more. (On loopback macOS doesn't
    /// report the bounce to the Link's connection, so this doesn't make it fail; `OSCUDPClientRecoveryTests` covers that.)
    func powerOff() {
        listener.withLock { $0?.cancel(); $0 = nil }
        responder.dropConnections()
    }

    /// Switches it back on, on the same port, with the same state (plus anything changed while it was off).
    func powerOn() async throws {
        let (listener, _) = try await Self.listen(on: NWEndpoint.Port(rawValue: port)!, responder: responder)
        self.listener.withLock { $0 = listener }
    }

    func update(_ change: @Sendable (inout State) -> Void) { responder.state.withLock { change(&$0) } }

    var queries: [String] { responder.state.withLock { $0.queries } }

    var writes: [(address: String, value: OSCArgument)] { responder.state.withLock { $0.writes } }

    /// Renames input channel `number` (1...16, or 1...32 on an X32) on the Mixer, as the operator would at its surface, and
    /// pushes the change to every client whose /xremote is still running.
    func rename(channel number: Int, to name: String) {
        update { $0.channels[number - 1].name = name }
        responder.push(OSCMessage(String(format: "/ch/%02d/config/name", number), [.string(name)]))
    }

    /// Recolors input channel `number` (1...16, or 1...32 on an X32), pushing the change like `rename`.
    func recolor(channel number: Int, to color: Int32) {
        update { $0.channels[number - 1].color = color }
        responder.push(OSCMessage(String(format: "/ch/%02d/config/color", number), [.int(color)]))
    }

    /// X32: patches USB card block `block` (0 = USB 1-8 … 3 = USB 25-32) to `bank`, pushing the change.
    func repatchCard(block: Int, to bank: Int32) {
        update { $0.cardBlocks?[block] = bank }
        responder.push(OSCMessage("/config/routing/CARD/" + Self.blockNames[block], [.int(bank)]))
    }

    /// X32: moves input channel `number` to source `source` (1-32 for In01-In32), pushing the change.
    func setSource(channel number: Int, to source: Int32) {
        update { $0.channels[number - 1].inputSource = source }
        responder.push(OSCMessage(String(format: "/ch/%02d/config/source", number), [.int(source)]))
    }

    static let blockNames = ["1-8", "9-16", "17-24", "25-32"]

    /// Renames the aux return (USB Channels 17 and 18).
    func renameAuxReturn(to name: String) {
        update { $0.auxReturn.name = name }
        responder.push(OSCMessage("/rtn/aux/config/name", [.string(name)]))
    }

    private final class Responder: Sendable {
        let state: Mutex<State>
        /// Clients that sent /xremote, and when each one's subscription runs out.
        private let subscribers = Mutex<[(connection: NWConnection, expires: Date)]>([])

        init(_ state: State) { self.state = Mutex(state) }

        /// Every connection served, so a power-off can close them all.
        private let connections = Mutex<[NWConnection]>([])

        func dropConnections() {
            let all = connections.withLock { list in defer { list = [] }; return list }
            for connection in all { connection.cancel() }
            subscribers.withLock { $0 = [] }
        }

        func push(_ message: OSCMessage) {
            guard state.withLock({ $0.answers }) else { return }
            let live = subscribers.withLock { $0.filter { $0.expires > Date() } }
            for subscriber in live {
                subscriber.connection.send(content: Data(message.encoded()), completion: .contentProcessed { _ in })
            }
        }

        private func subscribe(_ connection: NWConnection) {
            let lifetime = state.withLock { $0.xremoteLifetime }
            subscribers.withLock { list in
                list.removeAll { $0.connection === connection }
                list.append((connection, Date().addingTimeInterval(lifetime)))
            }
        }

        func serve(_ connection: NWConnection) {
            connections.withLock { list in if !list.contains(where: { $0 === connection }) { list.append(connection) } }
            connection.receiveMessage { [self] data, _, _, error in
                guard error == nil else { return }
                if let data, let query = try? OSCMessage(decoding: Array(data)), query.address == "/xremote" {
                    if state.withLock({ $0.answers }) { subscribe(connection) }
                    state.withLock { $0.queries.append("/xremote") }
                } else if let data, let message = try? OSCMessage(decoding: Array(data)), let value = message.arguments.first {
                    // A set: remember it, answer nothing (as the X32 does).
                    state.withLock { $0.writes.append((message.address, value)); $0.set[message.address] = value }
                } else if let data, let query = try? OSCMessage(decoding: Array(data)), let reply = reply(to: query) {
                    connection.send(content: Data(reply.encoded()), completion: .contentProcessed { _ in })
                }
                serve(connection)
            }
        }

        private func reply(to query: OSCMessage) -> OSCMessage? {
            state.withLock { state in
                state.queries.append(query.address)
                guard state.answers else { return nil }
                if let value = state.set[query.address] { return OSCMessage(query.address, [value]) }
                let parts = query.address.split(separator: "/").map(String.init)
                switch parts {
                case ["xinfo"]:
                    return OSCMessage("/xinfo", ["127.0.0.1", .string(state.networkName), .string(state.model), .string(state.firmware)])
                case let p where p.count == 4 && p[0] == "ch":
                    guard let number = Int(p[1]), state.channels.indices.contains(number - 1) else { return nil }
                    guard state.answersMixState || (p[2] == "config" && p[3] != state.inputSourceField) else { return nil }
                    if state.reportsFaderAsInt, p[2] == "mix", p[3] == "fader" { return OSCMessage(query.address, [.int(1)]) }
                    return Self.answer(query.address, section: p[2], field: p[3], channel: state.channels[number - 1], inputSourceField: state.inputSourceField)
                case let p where p.count == 3 && p[0] == "headamp" && p[2] == "gain":
                    guard let index = Int(p[1]), state.headampGains.indices.contains(index) else { return nil }
                    return OSCMessage(query.address, [.float(state.headampGains[index])])
                case let p where p.count == 5 && p[0] == "ch" && p[2] == "mix":
                    guard let number = Int(p[1]), state.channels.indices.contains(number - 1), let send = Int(p[3]), (1...16).contains(send) else { return nil }
                    let channel = state.channels[number - 1]
                    switch p[4] {
                    case "level": return OSCMessage(query.address, [.float(channel.sendLevels[send - 1])])
                    case "type" where send % 2 == 1: return OSCMessage(query.address, [.int(channel.sendTypes[send / 2])])
                    default: return nil
                    }
                case let p where p.count == 3 && p[0] == "-ha" && p[2] == "index" && state.inputSourceField == "source":
                    guard let index = Int(p[1]), state.headampOfChannel.indices.contains(index) else { return nil }
                    return OSCMessage(query.address, [.int(state.headampOfChannel[index])])
                case let p where p.count == 4 && p[0] == "config" && p[1] == "routing" && (p[2] == "CARD" || p[2] == "IN"):
                    guard let blocks = p[2] == "CARD" ? state.cardBlocks : state.inputBlocks,
                          let index = FakeXAirMixer.blockNames.firstIndex(of: p[3]) else { return nil }
                    return OSCMessage(query.address, [.int(blocks[index])])
                case let p where p.count == 4 && p[0] == "rtn" && p[1] == "aux" && state.hasAuxReturn:
                    guard state.answersMixState || p[2] == "config" else { return nil }
                    return Self.answer(query.address, section: p[2], field: p[3], channel: state.auxReturn, inputSourceField: nil)
                default:
                    return nil
                }
            }
        }

        private static func answer(_ address: String, section: String, field: String, channel: Channel, inputSourceField: String?) -> OSCMessage? {
            switch (section, field) {
            case ("config", "name"): OSCMessage(address, [.string(channel.name)])
            case ("config", "color"): OSCMessage(address, [.int(channel.color)])
            case ("config", let f) where f == inputSourceField: OSCMessage(address, [.int(channel.inputSource)])
            case ("mix", "on"): OSCMessage(address, [.int(channel.on)])
            case ("mix", "fader"): OSCMessage(address, [.float(channel.fader)])
            case ("mix", "mlevel"): OSCMessage(address, [.float(channel.monoLevel)])
            case ("gate", "thr"): OSCMessage(address, [.float(channel.gateThreshold)])
            case ("dyn", "thr"): OSCMessage(address, [.float(channel.compressorThreshold)])
            case ("gate", "keysrc"): OSCMessage(address, [.int(channel.gateKey)])
            case ("dyn", "keysrc"): OSCMessage(address, [.int(channel.compressorKey)])
            default: nil
            }
        }
    }
}

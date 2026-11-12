import Foundation
import OSC

/// The scene files of the Mixer Link test bench (`tools/mixer-sim/scenes/<name>.json`, described in its README),
/// loaded into the fake mixers, so the drivers are tested against the same scenes the simulator answers from.
/// A key a scene leaves out takes the simulator's default (`xair.py`, `x32.py`, `wing.py` there), not the fake's.
enum SimScene {
    /// An X-Air scene (`"family": "xair"`) as the fake X-Air's state.
    static func xAir(_ name: String) throws -> FakeXAirMixer.State { try xAir(json: Data(contentsOf: url(name))) }

    /// A key of a scene this loader doesn't read yet. Loading throws it, so no test runs on half a scene: teach the
    /// loader the key (as the simulator reads it) before a scene uses it.
    struct UnreadKey: Error, Equatable { var key: String }

    static func xAir(json: Data) throws -> FakeXAirMixer.State {
        try refuseUnreadKeys(json, read: [
            "": ["family", "about", "network_name", "model", "firmware", "channels", "aux_return", "headamps", "links", "link_preamps"],
            "channels": ["channel", "name", "color"], "aux_return": ["name", "color"], "headamps": ["headamp", "gain_db"],
        ])
        let scene = try JSONDecoder().decode(XAirScene.self, from: json)
        var state = FakeXAirMixer.State()
        state.networkName = scene.network_name ?? "XR18"
        state.model = scene.model ?? "XR18"
        state.firmware = scene.firmware ?? "1.26"
        // The simulator's default: USB 1-16 carry channels 1-16, 17-18 the aux return.
        state.usbRouting = (0..<18).map { [Int32($0), 0] }
        for entry in scene.channels ?? [] {
            if let name = entry.name { state.channels[entry.channel - 1].name = name }
            if let color = entry.color { state.channels[entry.channel - 1].color = color }
        }
        if let name = scene.aux_return?.name { state.auxReturn.name = name }
        if let color = scene.aux_return?.color { state.auxReturn.color = color }
        // `/headamp/01..18/gain` as the X-Air's 0...1: -12 to +60 dB (1-16), -12 to +20 dB (17-18). Default 0 dB.
        func gain(_ headamp: Int, _ db: Double) -> Float { Float((db + 12) / (headamp >= 17 ? 32 : 72)) }
        for headamp in 1...18 { state.headampGains[headamp] = gain(headamp, 0) }
        for entry in scene.headamps ?? [] { state.headampGains[entry.headamp] = gain(entry.headamp, entry.gain_db) }
        // Stereo links, and whether they link the preamps too. The fake answers what a client set, so they go there.
        for pair in scene.links ?? [] { state.set["/config/chlink/\(pair)"] = .int(1) }
        if scene.link_preamps == true { state.set["/config/linkcfg/preamp"] = .int(1) }
        return state
    }

    /// An X32 scene (`"family": "x32"`) as the fake X32's state.
    static func x32(_ name: String) throws -> FakeXAirMixer.State { try x32(json: Data(contentsOf: url(name))) }

    static func x32(json: Data) throws -> FakeXAirMixer.State {
        try refuseUnreadKeys(json, read: [
            "": ["family", "about", "network_name", "model", "firmware", "channels", "card_blocks", "input_blocks", "headamps", "links", "link_preamps"],
            "channels": ["channel", "name", "color", "source", "headamp"], "headamps": ["headamp", "gain_db"],
        ])
        let scene = try JSONDecoder().decode(X32Scene.self, from: json)
        var state = FakeXAirMixer.State.x32(model: scene.model ?? "X32")
        state.networkName = scene.network_name ?? "X32"
        state.firmware = scene.firmware ?? "4.06"
        for entry in scene.channels ?? [] {
            if let name = entry.name { state.channels[entry.channel - 1].name = name }
            if let color = entry.color { state.channels[entry.channel - 1].color = color }
            if let source = entry.source { state.channels[entry.channel - 1].inputSource = source }
            if let headamp = entry.headamp { state.headampOfChannel[entry.channel - 1] = headamp }
        }
        // `/headamp/000..127/gain` as the X32's 0...1 over -12 to +60 dB. Default 0 dB.
        func gain(_ db: Double) -> Float { Float((db + 12) / 72) }
        state.headampGains = Array(repeating: gain(0), count: 128)
        for entry in scene.headamps ?? [] { state.headampGains[entry.headamp] = gain(entry.gain_db) }
        // The bank each block of 8 carries (`/config/routing/CARD/1-8` … and `IN/…`); a block left out keeps AN1-32.
        for (block, bank) in (scene.card_blocks ?? []).enumerated() { state.cardBlocks?[block] = bank }
        for (block, bank) in (scene.input_blocks ?? []).enumerated() { state.inputBlocks?[block] = bank }
        for pair in scene.links ?? [] { state.set["/config/chlink/\(pair)"] = .int(1) }
        if scene.link_preamps == true { state.set["/config/linkcfg/hadly"] = .int(1) }
        return state
    }

    /// A WING scene (`"family": "wing"`) as the fake WING's state. The fake answers 0.0.0.0 as its address, where the
    /// simulator answers the host's own.
    static func wing(_ name: String) throws -> FakeWing.State { try wing(json: Data(contentsOf: url(name))) }

    static func wing(json: Data) throws -> FakeWing.State {
        // `channels` is let through unread: the driver names USB Channels from Sources and never asks for a channel.
        try refuseUnreadKeys(json, read: [
            "": ["family", "about", "network_name", "model", "serial", "firmware", "sources", "usb_outputs", "channels"],
            "sources": ["source", "name", "color"], "usb_outputs": ["usb", "source"], "channels": ["channel", "name", "color", "input"],
        ])
        let scene = try JSONDecoder().decode(WingScene.self, from: json)
        var state = FakeWing.State()
        state.identity = ["WING", "0.0.0.0", scene.network_name ?? "WING", scene.model ?? "ngc-full", scene.serial ?? "0", scene.firmware ?? "3.1.1"]
            .joined(separator: ",")
        // "LCL/1" as its group and number.
        func parts(_ source: String) -> (group: String, number: Int) {
            let parts = source.split(separator: "/")
            return (parts.first.map { $0.uppercased() } ?? "", parts.last.flatMap { Int($0) } ?? 0)
        }
        // A USB output the scene leaves out is off.
        var outputs = Dictionary(uniqueKeysWithValues: (1...48).map { ($0, (group: "OFF", number: 1)) })
        for entry in scene.usb_outputs ?? [] { outputs[entry.usb] = parts(entry.source) }
        for (usb, source) in outputs {
            state.replies["/io/out/USB/\(usb)/grp"] = [.string(source.group)]
            state.replies["/io/out/USB/\(usb)/in"] = FakeWing.intReply(source.number)
            // A Source the scene leaves out has an empty name and color 1; a mix (MAIN, BUS, …) is no Source.
            guard sourceGroups.contains(source.group) else { continue }
            state.replies["/io/in/\(source.group)/\(source.number)/name"] = [.string("")]
            state.replies["/io/in/\(source.group)/\(source.number)/col"] = FakeWing.intReply(1)
        }
        for entry in scene.sources ?? [] {
            let source = parts(entry.source)
            state.replies["/io/in/\(source.group)/\(source.number)/name"] = [.string(entry.name ?? "")]
            state.replies["/io/in/\(source.group)/\(source.number)/col"] = FakeWing.intReply(entry.color ?? 1)
        }
        return state
    }

    /// Throws `UnreadKey` for a key of the scene that isn't in `read`: the top level's under "", and those of each
    /// entry of a list (or of an object) under its key.
    private static func refuseUnreadKeys(_ json: Data, read: [String: Set<String>]) throws {
        guard let scene = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { return }
        func check(_ entry: [String: Any], _ path: String) throws {
            if let key = entry.keys.sorted().first(where: { read[path]?.contains($0) != true }) {
                throw UnreadKey(key: path.isEmpty ? key : "\(path).\(key)")
            }
        }
        try check(scene, "")
        for (key, value) in scene {
            for entry in (value as? [[String: Any]]) ?? [value as? [String: Any]].compactMap({ $0 }) { try check(entry, key) }
        }
    }

    /// `tools/mixer-sim/scenes/<name>.json`, found from this file's place in the repository.
    private static func url(_ name: String, file: String = #filePath) -> URL {
        var root = URL(fileURLWithPath: file)
        // Support/ -> MixerLinkTests/ -> Tests/ -> ShowRecorderKit/ -> Packages/ -> the repository.
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("tools/mixer-sim/scenes/\(name).json")
    }

    private struct Headamp: Decodable {
        var headamp: Int
        var gain_db: Double
    }

    private struct X32Scene: Decodable {
        var network_name: String?
        var model: String?
        var firmware: String?
        var channels: [Channel]?
        var card_blocks: [Int32]?
        var input_blocks: [Int32]?
        var headamps: [Headamp]?
        var links: [String]?
        var link_preamps: Bool?

        struct Channel: Decodable {
            var channel: Int
            var name: String?
            var color: Int32?
            var source: Int32?
            var headamp: Int32?
        }
    }

    /// The WING's groups that carry a named, colored Source (`SOURCE_GROUPS` in `tools/mixer-sim/wing.py`).
    private static let sourceGroups: Set<String> = ["LCL", "AUX", "A", "B", "C", "SC", "USB", "CRD", "MOD", "PLAY", "AES", "USR", "OSC"]

    private struct WingScene: Decodable {
        var network_name: String?
        var model: String?
        var serial: String?
        var firmware: String?
        var sources: [Source]?
        var usb_outputs: [USBOutput]?

        struct Source: Decodable {
            var source: String
            var name: String?
            var color: Int?
        }

        struct USBOutput: Decodable {
            var usb: Int
            var source: String
        }
    }

    private struct XAirScene: Decodable {
        var network_name: String?
        var model: String?
        var firmware: String?
        var channels: [Strip]?
        var aux_return: Strip?
        var headamps: [Headamp]?
        var links: [String]?
        var link_preamps: Bool?

        struct Strip: Decodable {
            /// 1-16; the aux return has none.
            var channel: Int = 0
            var name: String?
            var color: Int32?

            enum CodingKeys: String, CodingKey { case channel, name, color }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                channel = try values.decodeIfPresent(Int.self, forKey: .channel) ?? 0
                name = try values.decodeIfPresent(String.self, forKey: .name)
                color = try values.decodeIfPresent(Int32.self, forKey: .color)
            }
        }
    }
}

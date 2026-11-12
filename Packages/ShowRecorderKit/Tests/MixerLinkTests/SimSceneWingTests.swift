import Foundation
import MixerLink
import Testing

/// The WING scene the Mixer Link test bench ships (`tools/mixer-sim/scenes/wing-band.json`), loaded into the fake
/// WING, so the driver is checked against the same band the simulator answers with. This checks how the Swift side
/// reads the scene file, not what the Python simulator sends, and nothing here has met a real WING.
@Suite("mixer-sim scene: WING band")
struct SimSceneWingTests {
    static func driver(_ wing: FakeWing) -> WingDriver {
        WingDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: wing.port), oscPort: wing.oscPort, timeout: Loopback.replyTimeout)
    }

    @Test("The driver identifies the scene's Mixer and names and colors its 48 USB Channels from the Sources patched to them")
    func namesAndColors() async throws {
        let wing = try await FakeWing(SimScene.wing("wing-band"))
        let driver = Self.driver(wing)

        #expect(try await driver.identify() == MixerIdentity(networkName: "FOH-WING", model: "ngc-full", firmware: "3.1.1"))
        let sources = try await driver.sources(usbChannelCount: 48)

        #expect(sources.count == 48)
        func label(_ source: Source?) -> (String, MixerColor)? { source.map { ($0.name, $0.color) } }
        #expect(label(sources[safe: 0]) ?? ("", .off) == ("Kick", MixerColor(hue: .red, inverted: false)))
        #expect(sources[safe: 0]?.routedFrom == "LCL:1")
        #expect(label(sources[safe: 9]) ?? ("", .off) == ("Keys", MixerColor(hue: .cyan, inverted: false)))
        #expect(label(sources[safe: 12]) ?? ("", .off) == ("Playback L", MixerColor(hue: .magenta, inverted: false)))
        #expect(sources[safe: 12]?.routedFrom == "A:1")
        #expect(sources[safe: 20]?.name == "USB 21", "a USB output the scene leaves out is off")
        #expect(sources[safe: 46]?.name == "USB 47", "the main mix on USB 47 keeps its USB Channel name")
        #expect(sources[safe: 46]?.hasMixerName == false)
    }

    @Test("A patched Source the scene doesn't describe has no name and color 1, as on the simulator")
    func undescribedSource() async throws {
        let json = #"{"family": "wing", "usb_outputs": [{"usb": 1, "source": "LCL/3"}]}"#
        let wing = try await FakeWing(SimScene.wing(json: Data(json.utf8)))

        let source = try await Self.driver(wing).sources(usbChannelCount: 1).first

        #expect(source?.name == "USB 01")
        #expect(source?.color == MixerColor(hue: .blue, inverted: false))
        #expect(source?.routedFrom == "LCL:3")
    }

    @Test("A scene with a key the loader doesn't read yet is refused, so a test never runs on half a scene",
          arguments: [#"{"family": "wing", "headamps": [{"headamp": 1, "gain_db": 30}]}"#,
                      #"{"family": "wing", "sources": [{"source": "LCL/1", "icon": 3}]}"#])
    func refusesUnreadKeys(json: String) {
        #expect(throws: SimScene.UnreadKey.self) { try SimScene.wing(json: Data(json.utf8)) }
    }
}

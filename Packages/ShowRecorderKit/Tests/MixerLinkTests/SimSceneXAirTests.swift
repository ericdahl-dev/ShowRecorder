import Foundation
import MixerLink
import Testing

/// The XR18 scene the Mixer Link test bench ships (`tools/mixer-sim/scenes/xr18-band.json`), loaded into the fake
/// X-Air, so the driver is checked against the same band the simulator answers with. This checks how the Swift side
/// reads the scene file, not what the Python simulator sends.
@Suite("mixer-sim scene: XR18 band")
struct SimSceneXAirTests {
    @Test("The driver identifies the scene's Mixer and names and colors its 18 USB Channels")
    func namesAndColors() async throws {
        let mixer = try await FakeXAirMixer(SimScene.xAir("xr18-band"))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.identify() == MixerIdentity(networkName: "FOH-XR18", model: "XR18", firmware: "1.26"))
        let sources = try await driver.sources(usbChannelCount: 18)

        #expect(sources.count == 18)
        func label(_ source: Source?) -> (String, MixerColor)? { source.map { ($0.name, $0.color) } }
        #expect(label(sources[safe: 0]) ?? ("", .off) == ("Kick", MixerColor(hue: .red, inverted: false)))
        #expect(label(sources[safe: 2]) ?? ("", .off) == ("Hat", MixerColor(hue: .red, inverted: true)))
        #expect(label(sources[safe: 10]) ?? ("", .off) == ("Lead Vox", MixerColor(hue: .blue, inverted: false)))
        #expect(sources[safe: 12]?.name == "USB 13", "a channel the scene leaves out keeps its USB Channel name")
        #expect(sources[safe: 12]?.hasMixerName == false)
        #expect(label(sources[safe: 16]) ?? ("", .off) == ("Playback", MixerColor(hue: .magenta, inverted: false)))
        #expect(label(sources[safe: 17]) ?? ("", .off) == ("Playback", MixerColor(hue: .magenta, inverted: false)))
    }

    @Test("The driver reads the scene's preamp gains; a preamp the scene leaves out is at 0 dB")
    func preampGains() async throws {
        let mixer = try await FakeXAirMixer(SimScene.xAir("xr18-band"))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.headamp(ofChannel: 11) == 11)
        #expect(try await driver.gainDb(ofHeadamp: 1) == 32)
        #expect(try await driver.gainDb(ofHeadamp: 11) == 38.5)
        #expect(try await driver.gainDb(ofHeadamp: 3) == 0)
    }

    @Test("The scene's stereo-linked overheads (5-6) are one lane on one preamp; other channels are on their own")
    func linkedOverheads() async throws {
        let mixer = try await FakeXAirMixer(SimScene.xAir("xr18-band"))
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        #expect(try await driver.lane(ofChannel: 6) == 5)
        #expect(try await driver.preamp(ofChannel: 6) == 5)
        #expect(try await driver.lane(ofChannel: 8) == nil)
        #expect(try await driver.preamp(ofChannel: 8) == 8)
    }

    @Test("A scene with a key the loader doesn't read yet is refused, so a test never runs on half a scene",
          arguments: [#"{"family": "xair", "usb_routing": [{"usb": 18, "source": 26}]}"#,
                      #"{"family": "xair", "channels": [{"channel": 2, "insrc": 5}]}"#])
    func refusesUnreadKeys(json: String) {
        #expect(throws: SimScene.UnreadKey.self) { try SimScene.xAir(json: Data(json.utf8)) }
    }
}

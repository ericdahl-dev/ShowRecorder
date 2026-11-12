import Foundation
import MixerLink
import Testing

/// The X32 scene the Mixer Link test bench ships (`tools/mixer-sim/scenes/x32-band.json`), loaded into the fake X32,
/// so the driver is checked against the same band the simulator answers with. This checks how the Swift side reads
/// the scene file, not what the Python simulator sends.
@Suite("mixer-sim scene: X32 band")
struct SimSceneX32Tests {
    static func driver(_ mixer: FakeXAirMixer) -> X32Driver {
        X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
    }

    @Test("The driver identifies the scene's Mixer and names and colors its 32 USB Channels")
    func namesAndColors() async throws {
        let mixer = try await FakeXAirMixer(SimScene.x32("x32-band"))
        let driver = Self.driver(mixer)

        #expect(try await driver.identify() == MixerIdentity(networkName: "FOH-X32", model: "X32", firmware: "4.06"))
        let sources = try await driver.sources(usbChannelCount: 32)

        #expect(sources.count == 32)
        func label(_ source: Source?) -> (String, MixerColor)? { source.map { ($0.name, $0.color) } }
        #expect(label(sources[safe: 0]) ?? ("", .off) == ("Kick", MixerColor(hue: .red, inverted: false)))
        #expect(label(sources[safe: 2]) ?? ("", .off) == ("Hat", MixerColor(hue: .red, inverted: true)))
        #expect(label(sources[safe: 15]) ?? ("", .off) == ("Talkback", MixerColor(hue: .white, inverted: false)))
        #expect(sources[safe: 20]?.name == "USB 21", "a channel the scene leaves out keeps its USB Channel name")
        #expect(sources[safe: 20]?.hasMixerName == false)
    }

    @Test("The scene's second vocal mix (channel 17) shares the lead vocal's input and preamp, and the gains are the scene's")
    func sharedPreampAndGains() async throws {
        let mixer = try await FakeXAirMixer(SimScene.x32("x32-band"))
        let driver = Self.driver(mixer)

        let sources = try await driver.sources(usbChannelCount: 32)
        #expect(sources[safe: 10]?.name == "Lead Vox", "USB 11 carries input 11: the lead vocal, the first channel on it")
        #expect(sources[safe: 16]?.name == "USB 17", "channel 17 listens to input 11, so no channel is on USB 17's input")
        #expect(try await driver.headamp(ofChannel: 11) == 10)
        #expect(try await driver.headamp(ofChannel: 17) == 10)
        #expect(try await driver.gainDb(ofHeadamp: 10) == 38.5)
        #expect(try await driver.gainDb(ofHeadamp: 0) == 30)
        #expect(try await driver.gainDb(ofHeadamp: 5) == 0, "a preamp the scene leaves out is at 0 dB")
    }

    @Test("The scene's stereo-linked keys (9-10) are one lane on one preamp; other channels are on their own")
    func linkedKeys() async throws {
        let mixer = try await FakeXAirMixer(SimScene.x32("x32-band"))
        let driver = Self.driver(mixer)

        #expect(try await driver.lane(ofChannel: 10) == 9)
        #expect(try await driver.preamp(ofChannel: 10) == 8, "channel 9's preamp, numbered from 0")
        #expect(try await driver.lane(ofChannel: 12) == nil)
        #expect(try await driver.preamp(ofChannel: 12) == 11)
    }

    @Test("The scene's card and input routing reaches the driver: with the card on AES50 A, no USB Channel is named")
    func cardRouting() async throws {
        let json = #"{"family": "x32", "channels": [{"channel": 1, "name": "Kick"}], "card_blocks": [4, 5, 6, 7]}"#
        let mixer = try await FakeXAirMixer(SimScene.x32(json: Data(json.utf8)))

        let sources = try await Self.driver(mixer).sources(usbChannelCount: 32)

        #expect(sources[safe: 0]?.name == "USB 01")
    }

    @Test("A scene with a key the loader doesn't read yet is refused, so a test never runs on half a scene",
          arguments: [#"{"family": "x32", "osc": {"/ch/01/gate/on": [1]}}"#,
                      #"{"family": "x32", "channels": [{"channel": 2, "fader": 0.5}]}"#])
    func refusesUnreadKeys(json: String) {
        #expect(throws: SimScene.UnreadKey.self) { try SimScene.x32(json: Data(json.utf8)) }
    }
}

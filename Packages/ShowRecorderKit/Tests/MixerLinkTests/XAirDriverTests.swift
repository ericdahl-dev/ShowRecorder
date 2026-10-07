import MixerLink
import Testing

@Suite("X-Air driver")
struct XAirDriverTests {
    @Test("Identifies the Mixer from /xinfo")
    func identifiesMixer() async throws {
        let mixer = try await FakeXAirMixer()
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let identity = try await driver.identify()

        #expect(identity == MixerIdentity(networkName: "FOH-XR18", model: "XR18", firmware: "1.22"))
    }

    @Test("Reads a Source name and color for each of the 18 USB Channels")
    func readsSourcesForEighteenUSBChannels() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1)        // red
        state.channels[6] = .init(name: "Lead Vocal", color: 11) // yellow, inverted
        state.auxReturn = .init(name: "Playback", color: 4)      // blue
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let sources = try await driver.sources(usbChannelCount: 18)

        #expect(sources.count == 18)
        #expect(sources[0] == Source(name: "Kick", color: MixerColor(hue: .red, inverted: false)))
        #expect(sources[6] == Source(name: "Lead Vocal", color: MixerColor(hue: .yellow, inverted: true)))
        #expect(sources[16] == Source(name: "Playback", color: MixerColor(hue: .blue, inverted: false)))
        #expect(sources[17] == Source(name: "Playback", color: MixerColor(hue: .blue, inverted: false)))
    }

    @Test("A Source with an empty name falls back to its USB Channel number")
    func emptyNameFallsBackToUSBChannel() async throws {
        let mixer = try await FakeXAirMixer()
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let sources = try await driver.sources(usbChannelCount: 18)

        #expect(sources[6].name == "USB 07")
        #expect(sources[6].hasMixerName == false)
        #expect(sources[17].name == "USB 18")
    }
}

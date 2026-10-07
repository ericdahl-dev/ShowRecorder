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
        func label(_ source: Source) -> (String, MixerColor) { (source.name, source.color) }
        #expect(label(sources[0]) == ("Kick", MixerColor(hue: .red, inverted: false)))
        #expect(label(sources[6]) == ("Lead Vocal", MixerColor(hue: .yellow, inverted: true)))
        #expect(label(sources[16]) == ("Playback", MixerColor(hue: .blue, inverted: false)))
        #expect(label(sources[17]) == ("Playback", MixerColor(hue: .blue, inverted: false)))
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

    @Test("Reads each Source's mute, fader and input source")
    func readsMuteFaderAndInputSource() async throws {
        var state = FakeXAirMixer.State()
        state.channels[2] = .init(name: "Hat", color: 3, on: 0, fader: 0.5, inputSource: 2)
        state.auxReturn = .init(name: "Playback", color: 4, on: 1, fader: 0.25)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let sources = try await driver.sources(usbChannelCount: 18)

        #expect(sources[2].isMuted == true)
        #expect(sources[2].fader == 0.5)
        #expect(sources[2].inputSource == 2)
        #expect(sources[17].isMuted == false)
        #expect(sources[17].fader == 0.25)
        #expect(sources[17].inputSource == nil, "the aux return has no input source setting")
    }

    @Test("A Mixer that ignores mix-state queries still gives names, without a timeout per query")
    func missingMixStateIsSkippedQuickly() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1)
        state.answersMixState = false
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: .milliseconds(200))

        let clock = ContinuousClock()
        var sources: [Source] = []
        let elapsed = try await clock.measure { sources = try await driver.sources(usbChannelCount: 18) }

        #expect(sources[0].name == "Kick")
        #expect(sources.allSatisfy { $0.isMuted == nil && $0.fader == nil && $0.inputSource == nil })
        #expect(elapsed < .seconds(1), "one timeout, not one per Source")
    }

    @Test("An unexpected reply for mute, fader or input source leaves that value unknown, not the Link down")
    func oddMixStateReplyIsUnknown() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1, on: 0)
        state.reportsFaderAsInt = true
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let sources = try await driver.sources(usbChannelCount: 18)

        #expect(sources[0].name == "Kick")
        #expect(sources[0].isMuted == true)
        #expect(sources[0].fader == nil)
    }
}

import MixerLink
import Testing

@Suite("X32 driver")
struct X32DriverTests {
    @Test("Identifies the Mixer from /xinfo and knows an X32 sends 32 USB Channels, all nameable")
    func identifiesMixer() async throws {
        let mixer = try await FakeXAirMixer(.x32())
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let identity = try await driver.identify()

        #expect(identity == MixerIdentity(networkName: "FOH-X32", model: "X32", firmware: "4.06"))
        #expect(driver.capabilities(for: identity) == MixerCapabilities(usbChannelCount: 32, nameableUSBChannelCount: 32))
    }

    @Test("Reads a Source name and color for each of the 32 USB Channels, from input channels 1 to 32 (the card's default patch)")
    func readsSourcesForThirtyTwoUSBChannels() async throws {
        var state = FakeXAirMixer.State.x32()
        state.channels[0] = .init(name: "Kick", color: 1)          // red
        state.channels[16] = .init(name: "Lead Vocal", color: 11)  // yellow, inverted
        state.channels[31] = .init(name: "Audience R", color: 6)   // cyan
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let sources = try await driver.sources(usbChannelCount: 32)

        #expect(sources.count == 32)
        func label(_ source: Source?) -> (String, MixerColor)? { source.map { ($0.name, $0.color) } }
        #expect(label(sources[safe: 0]) ?? ("", .off) == ("Kick", MixerColor(hue: .red, inverted: false)))
        #expect(label(sources[safe: 16]) ?? ("", .off) == ("Lead Vocal", MixerColor(hue: .yellow, inverted: true)))
        #expect(label(sources[safe: 31]) ?? ("", .off) == ("Audience R", MixerColor(hue: .cyan, inverted: false)))
        #expect(sources[safe: 5]?.name == "USB 06", "an unnamed channel keeps its USB Channel name")
        #expect(sources[safe: 5]?.hasMixerName == false)
    }

    @Test("Reads each Source's mute, fader and input source (the X32's config/source)")
    func readsMuteFaderAndInputSource() async throws {
        var state = FakeXAirMixer.State.x32()
        state.channels[24] = .init(name: "Keys L", color: 5, on: 0, fader: 0.5, inputSource: 33)
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let sources = try await driver.sources(usbChannelCount: 32)

        #expect(sources[safe: 24]?.isMuted == true)
        #expect(sources[safe: 24]?.fader == 0.5)
        #expect(sources[safe: 24]?.inputSource == 33)
        #expect(!mixer.queries.contains { $0.hasSuffix("/insrc") }, "the X32 has no insrc")
    }

    @Test("Name and color changes pushed for any of the 32 channels reach their USB Channel")
    func pushedChangesReachTheirUSBChannel() async throws {
        let mixer = try await FakeXAirMixer(.x32())
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))
        var changes = driver.sourceChanges().makeAsyncIterator()
        try await driver.renewLiveUpdates()

        mixer.rename(channel: 32, to: "Audience R")
        mixer.recolor(channel: 17, to: 2)

        #expect(await changes.next() == SourceChange(usbChannel: 32, name: "Audience R"))
        #expect(await changes.next() == SourceChange(usbChannel: 17, color: MixerColor(hue: .green, inverted: false)))
    }
}

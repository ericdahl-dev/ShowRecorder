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

    @Test("Reads a Source name and color for each of the 32 USB Channels; on the default patch, input channels 1 to 32")
    func readsSourcesForThirtyTwoUSBChannels() async throws {
        var state = FakeXAirMixer.State.x32()
        state.channels[0] = .init(name: "Kick", color: 1, inputSource: 1)          // red
        state.channels[16] = .init(name: "Lead Vocal", color: 11, inputSource: 17)  // yellow, inverted
        state.channels[31] = .init(name: "Audience R", color: 6, inputSource: 32)   // cyan
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
        state.channels[24] = .init(name: "Keys L", color: 5, on: 0, fader: 0.5, inputSource: 25)
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let sources = try await driver.sources(usbChannelCount: 32)

        #expect(sources[safe: 24]?.isMuted == true)
        #expect(sources[safe: 24]?.fader == 0.5)
        #expect(sources[safe: 24]?.inputSource == 25)
        #expect(!mixer.queries.contains { $0.hasSuffix("/insrc") }, "the X32 has no insrc")
    }

    @Test("Name and color changes pushed for any of the 32 channels reach their USB Channel")
    func pushedChangesReachTheirUSBChannel() async throws {
        let mixer = try await FakeXAirMixer(.x32())
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))
        _ = try await driver.sources(usbChannelCount: 32)   // as the Link does before live updates
        var changes = driver.sourceChanges().makeAsyncIterator()
        try await driver.renewLiveUpdates()

        mixer.rename(channel: 32, to: "Audience R")
        mixer.recolor(channel: 17, to: 2)

        #expect(await changes.next() == SourceChange(usbChannel: 32, name: "Audience R"))
        #expect(await changes.next() == SourceChange(usbChannel: 17, color: MixerColor(hue: .green, inverted: false)))
    }

    @Test("A re-patched desk: each USB Channel is named after the channel actually on it (#20)")
    func repatchedDesk() async throws {
        var state = FakeXAirMixer.State.x32()
        state.cardBlocks?[0] = 1                          // USB 1-8 carry AN9-16
        state.channels[8] = .init(name: "Tom 1", color: 4, inputSource: 9)
        state.channels[0] = .init(name: "Kick", color: 1, inputSource: 1)
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let sources = try await driver.sources(usbChannelCount: 32)

        #expect(sources[safe: 0]?.name == "Tom 1", "USB 1 carries input 9, channel 9")
        #expect(sources[safe: 8]?.name == "Tom 1", "USB 9 still carries AN9-16 too")
        #expect(!sources.contains { $0.name == "Kick" }, "AN1-8 isn't on the card any more")
    }

    @Test("A USB Channel that carries no input channel (an output, say) gets its USB Channel name, never another's")
    func outputOnTheCard() async throws {
        var state = FakeXAirMixer.State.x32()
        state.cardBlocks?[3] = 20                         // USB 25-32 carry OUT1-8
        state.channels[24] = .init(name: "Keys L", color: 5, inputSource: 25)
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))

        let sources = try await driver.sources(usbChannelCount: 32)

        #expect(sources[safe: 24]?.name == "USB 25")
        #expect(sources[safe: 24]?.hasMixerName == false)
    }

    @Test("A Mixer that doesn't answer its USB routing names no USB Channel, rather than guess the patch")
    func routingUnanswered() async throws {
        var state = FakeXAirMixer.State.x32()
        state.cardBlocks = nil
        state.channels[0] = .init(name: "Kick", color: 1, inputSource: 1)
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: .milliseconds(500))

        let sources = try await driver.sources(usbChannelCount: 32)

        #expect(sources.count == 32)
        #expect(sources.allSatisfy { !$0.hasMixerName })
    }

    @Test("On a re-patched desk a rename reaches the USB Channel the channel is on, not the one with its number")
    func renameFollowsTheRouting() async throws {
        var state = FakeXAirMixer.State.x32()
        state.cardBlocks?[0] = 1                          // USB 1-8 carry AN9-16
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))
        _ = try await driver.sources(usbChannelCount: 32)
        var changes = driver.sourceChanges().makeAsyncIterator()
        try await driver.renewLiveUpdates()

        mixer.rename(channel: 1, to: "Kick")              // channel 1 (AN1) is on no USB Channel now
        mixer.rename(channel: 9, to: "Tom 1")             // channel 9 (AN9) is on USB 1 and USB 9

        #expect(await changes.next() == SourceChange(usbChannel: 1, name: "Tom 1"))
        #expect(await changes.next() == SourceChange(usbChannel: 9, name: "Tom 1"))
    }

    @Test("Re-patching the card while linked renames the USB Channels it moved (routing kept current)")
    func repatchWhileLinked() async throws {
        var state = FakeXAirMixer.State.x32()
        state.channels[0] = .init(name: "Kick", color: 1, inputSource: 1)
        state.channels[8] = .init(name: "Tom 1", color: 4, inputSource: 9)
        let mixer = try await FakeXAirMixer(state)
        let driver = X32Driver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))
        let before = try await driver.sources(usbChannelCount: 32)
        #expect(before[safe: 0]?.name == "Kick")
        var changes = driver.sourceChanges().makeAsyncIterator()
        try await driver.renewLiveUpdates()

        mixer.repatchCard(block: 0, to: 1)                // USB 1-8 now carry AN9-16

        #expect(await changes.next() == SourceChange(usbChannel: 1, name: "Tom 1", color: MixerColor(hue: .blue, inverted: false)))
    }
}

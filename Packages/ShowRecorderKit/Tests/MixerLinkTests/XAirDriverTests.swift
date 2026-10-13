import MixerLink
import Testing

@Suite("X-Air driver")
struct XAirDriverTests {
    @Test("Identifies the Mixer from /xinfo")
    func identifiesMixer() async throws {
        let mixer = try await FakeXAirMixer()
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let identity = try await driver.identify()

        #expect(identity == MixerIdentity(networkName: "FOH-XR18", model: "XR18", firmware: "1.22"))
    }

    @Test("Reads a Source name and color for each of the 18 USB Channels")
    func readsSourcesForEighteenUSBChannels() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1)        // red
        state.channels[6] = .init(name: "Lead Vocal", color: 11) // yellow, inverted
        state.auxReturn = .init(name: "Playback", color: 4)      // blue
        state.usbRouting = Self.defaultRouting   // answered, so no read waits out its timeout (#462)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let sources = try await driver.sources(usbChannelCount: 18)

        #expect(sources.count == 18)
        func label(_ source: Source) -> (String, MixerColor) { (source.name, source.color) }
        #expect(label(sources[0]) == ("Kick", MixerColor(hue: .red, inverted: false)))
        #expect(label(sources[6]) == ("Lead Vocal", MixerColor(hue: .yellow, inverted: true)))
        #expect(label(sources[16]) == ("Playback", MixerColor(hue: .blue, inverted: false)))
        #expect(label(sources[17]) == ("Playback", MixerColor(hue: .blue, inverted: false)))
    }

    @Test("Reads one Source per USB Channel the device sends", arguments: [8, 16, 18])
    func readsOneSourcePerUSBChannel(count: Int) async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1)
        state.usbRouting = Self.defaultRouting   // answered, so no read waits out its timeout (#462)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let sources = try await driver.sources(usbChannelCount: count)

        #expect(sources.count == count)
        #expect(sources[0].name == "Kick")
    }

    @Test("USB Channels beyond the 18 the X-Air routes get their USB Channel name without asking the Mixer")
    func channelsBeyondEighteenFallBack() async throws {
        var state = FakeXAirMixer.State()
        state.auxReturn = .init(name: "Playback", color: 4)
        state.usbRouting = Self.defaultRouting   // answered, so no read waits out its timeout (#462)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let sources = try await driver.sources(usbChannelCount: 32)

        #expect(sources.count == 32)
        #expect(sources[17].name == "Playback")
        #expect(sources[18] == .fallback(usbChannel: 19))
        #expect(sources[31] == .fallback(usbChannel: 32))
        #expect(mixer.queries.filter { $0.hasPrefix("/rtn/aux/config/name") }.count == 2)
    }

    @Test("A Source with an empty name falls back to its USB Channel number")
    func emptyNameFallsBackToUSBChannel() async throws {
        var state = FakeXAirMixer.State()
        state.usbRouting = Self.defaultRouting   // answered, so no read waits out its timeout (#462)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

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
        state.usbRouting = Self.defaultRouting   // answered, so no read waits out its timeout (#462)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

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
        // A 1 s timeout, so a loaded machine can still answer the names (#323); missing mix state still costs one
        // timeout (under 3 s), not one per Source (18 s).
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: .seconds(1))

        let clock = ContinuousClock()
        var sources: [Source] = []
        let elapsed = try await clock.measure { sources = try await driver.sources(usbChannelCount: 18) }

        #expect(try #require(sources.first).name == "Kick")
        #expect(sources.allSatisfy { $0.isMuted == nil && $0.fader == nil && $0.inputSource == nil })
        #expect(elapsed < .seconds(3), "one timeout, not one per Source")
    }

    @Test("An unexpected reply for mute, fader or input source leaves that value unknown, not the Link down")
    func oddMixStateReplyIsUnknown() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1, on: 0)
        state.reportsFaderAsInt = true
        state.usbRouting = Self.defaultRouting   // answered, so no read waits out its timeout (#462)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let sources = try await driver.sources(usbChannelCount: 18)

        #expect(sources[0].name == "Kick")
        #expect(sources[0].isMuted == true)
        #expect(sources[0].fader == nil)
    }

    static let defaultRouting: [[Int32]] = (0..<18).map { [Int32($0), 0] }

    @Test("A re-patched XR18: each USB Channel is named after what's on it; a bus on USB gets its USB Channel name (#20)")
    func repatched() async throws {
        var state = FakeXAirMixer.State()
        state.usbRouting = Self.defaultRouting
        state.usbRouting?[0] = [4, 0]          // USB 1 carries Ch05
        state.usbRouting?[17] = [26, 10]       // USB 18 carries Bus1, POST
        state.channels[4] = .init(name: "Tom", color: 4)
        state.channels[0] = .init(name: "Kick", color: 1)
        state.auxReturn = .init(name: "Playback", color: 4)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let sources = try await driver.sources(usbChannelCount: 18)

        #expect(sources[safe: 0]?.name == "Tom")
        #expect(sources[safe: 4]?.name == "Tom", "USB 5 still carries Ch05")
        #expect(sources[safe: 16]?.name == "Playback")
        #expect(sources[safe: 17]?.name == "USB 18")
        #expect(sources[safe: 17]?.hasMixerName == false)
        #expect(!sources.contains { $0.name == "Kick" })
    }

    @Test("Firmware that doesn't answer the USB routing keeps the default: USB 1-16 channels 1-16, 17-18 the aux return")
    func routingUnanswered() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1)
        let mixer = try await FakeXAirMixer(state)   // usbRouting nil: no answer
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: .milliseconds(500))

        let sources = try await driver.sources(usbChannelCount: 18)

        #expect(sources[safe: 0]?.name == "Kick")
    }

    @Test("On a re-patched XR18 a rename reaches the USB Channel the channel is on; a re-patch renames what moved")
    func liveFollowsRouting() async throws {
        var state = FakeXAirMixer.State()
        state.usbRouting = Self.defaultRouting
        state.usbRouting?[0] = [4, 0]          // USB 1 carries Ch05
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        let sources = try await driver.sources(usbChannelCount: 18)
        #expect(sources[0].routedFrom == "ch:5" && sources[1].routedFrom == "ch:2" && sources[16].routedFrom == "aux")
        var changes = driver.sourceChanges().makeAsyncIterator()
        try await driver.renewLiveUpdates()

        mixer.rename(channel: 5, to: "Tom")
        #expect(await changes.next() == SourceChange(usbChannel: 1, name: "Tom"))
        #expect(await changes.next() == SourceChange(usbChannel: 5, name: "Tom"))

        mixer.rename(channel: 2, to: "Snare")
        mixer.repatchUSB(1, to: 1)             // USB 1 now carries Ch02
        #expect(await changes.next() == SourceChange(usbChannel: 2, name: "Snare"))
        #expect(await changes.next() == SourceChange(usbChannel: 1, name: "Snare", routedFrom: .some("ch:2")), "a re-patch says what the USB Channel carries now (#21)")
    }

    @Test("Pushed changes: a color reaches its USB Channel, a cleared name comes through empty, an aux return rename reaches USB 17 and 18")
    func pushedColorClearedNameAndAuxReturn() async throws {
        var state = FakeXAirMixer.State()
        state.usbRouting = Self.defaultRouting
        state.channels[3] = .init(name: "Tom", color: 1)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)
        _ = try await driver.sources(usbChannelCount: 18)   // as the Link does before live updates
        var changes = driver.sourceChanges().makeAsyncIterator()
        try await driver.renewLiveUpdates()

        mixer.recolor(channel: 4, to: 10)
        #expect(await changes.next() == SourceChange(usbChannel: 4, color: MixerColor(hue: .green, inverted: true)))
        mixer.rename(channel: 4, to: "")
        #expect(await changes.next() == SourceChange(usbChannel: 4, name: ""))
        mixer.renameAuxReturn(to: "Playback")
        #expect(await changes.next() == SourceChange(usbChannel: 17, name: "Playback"))
        #expect(await changes.next() == SourceChange(usbChannel: 18, name: "Playback"))
    }

    @Test("Asked for no Sources, as for a Mixer without multichannel USB, the driver asks the Mixer for no channel")
    func noSourcesAsksNothing() async throws {
        var state = FakeXAirMixer.State()
        state.model = "XR16"
        state.channels[0] = .init(name: "Kick", color: 1)
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: Loopback.replyTimeout)

        let sources = try await driver.sources(usbChannelCount: 0)

        #expect(sources.isEmpty)
        #expect(!mixer.queries.contains { $0.hasPrefix("/ch/") })
    }
}

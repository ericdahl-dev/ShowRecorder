import MixerLink
import Testing

@MainActor
@Suite("Mixer Link live updates")
struct MixerLinkLiveTests {
    /// Waits until `condition` holds, or gives up after `seconds`.
    func eventually(_ seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test("A rename on the Mixer reaches the Sources while the Link is up")
    func renameShowsUp() async throws {
        var state = FakeXAirMixer.State()
        state.channels[1] = .init(name: "Snare", color: 2)
        let mixer = try await FakeXAirMixer(state)
        let link = MixerLinkController()
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)

        #expect(await eventually { mixer.queries.contains("/xremote") })
        mixer.rename(channel: 2, to: "Snare Top")

        #expect(await eventually { link.sources[1].name == "Snare Top" })
        #expect(link.sources[1].hasMixerName)
    }

    @Test("The Link renews /xremote before it runs out, so renames keep arriving long after the first one lapsed")
    func renewsXremote() async throws {
        // Wide margins so a slow CI runner can't make it flaky (#283): renewals every 0.1 s against a 2 s lifetime,
        // and the rename only after the first registration has run out. It waits on conditions, not fixed sleeps.
        var state = FakeXAirMixer.State()
        state.xremoteLifetime = 2
        let mixer = try await FakeXAirMixer(state)
        let link = MixerLinkController(renewEvery: .milliseconds(100))
        let connected = ContinuousClock.now
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)

        #expect(await eventually(10) { mixer.queries.filter { $0 == "/xremote" }.count >= 4 })
        // Past the first registration's lifetime, so only a renewal can deliver the rename.
        let lapsed = connected + .milliseconds(2_300)
        if ContinuousClock.now < lapsed { try await Task.sleep(until: lapsed) }
        mixer.rename(channel: 3, to: "Hat")

        #expect(await eventually(10) { link.sources[2].name == "Hat" })
    }

    @Test("When the Mixer goes quiet the Link goes down, and when it is back the Sources are read again, including renames it missed")
    func lossAndResync() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1)
        let mixer = try await FakeXAirMixer(state)
        let link = MixerLinkController(timeout: .milliseconds(100), renewEvery: .milliseconds(100))
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)
        #expect(link.sources[0].name == "Kick")

        mixer.update { $0.answers = false }
        #expect(await eventually { link.status == .down(.noReply(host: "127.0.0.1")) })
        mixer.update { $0.channels[0].name = "Bass Drum" }  // renamed while nobody could hear it
        mixer.update { $0.answers = true }

        #expect(await eventually { link.identity != nil })
        #expect(link.sources.count == 18)
        #expect(link.sources[0].name == "Bass Drum")
        mixer.rename(channel: 2, to: "Snare")  // and live updates work again
        #expect(await eventually { link.sources[1].name == "Snare" })
    }

    @Test("Color changes and aux return renames are applied too, and a cleared name goes back to the USB default")
    func colorAuxAndClearedName() async throws {
        var state = FakeXAirMixer.State()
        state.channels[3] = .init(name: "Tom", color: 1)
        let mixer = try await FakeXAirMixer(state)
        let link = MixerLinkController()
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)
        #expect(await eventually { mixer.queries.contains("/xremote") })

        mixer.recolor(channel: 4, to: 10)
        mixer.renameAuxReturn(to: "Playback")
        mixer.rename(channel: 4, to: "")

        #expect(await eventually { link.sources[16].name == "Playback" && link.sources[17].name == "Playback" })
        #expect(await eventually { link.sources[3].name == "USB 04" })
        #expect(link.sources[3].hasMixerName == false)
        #expect(link.sources[3].color == MixerColor(hue: .green, inverted: true))
    }
}

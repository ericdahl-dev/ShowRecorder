import MixerLink
import Testing

@MainActor
@Suite("Mixer Link controller")
struct MixerLinkControllerTests {
    @Test("Connecting to a Mixer's address brings the Link up over Wi-Fi with its Sources")
    func connectBringsLinkUp() async throws {
        var state = FakeXAirMixer.State()
        state.channels[1] = .init(name: "Snare", color: 2)
        let mixer = try await FakeXAirMixer(state)
        let link = MixerLinkController()

        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)

        #expect(link.status == .up(MixerIdentity(networkName: "FOH-XR18", model: "XR18", firmware: "1.22"), path: .wifi))
        #expect(link.sources.count == 18)
        #expect(link.sources[1].name == "Snare")
        #expect(link.sources[0].name == "USB 01")
    }

    @Test("Reads one Source per USB Channel the Armed device sends", arguments: [8, 16, 18, 32])
    func readsSourcesForArmedCount(count: Int) async throws {
        let mixer = try await FakeXAirMixer()
        let link = MixerLinkController()

        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: count)

        #expect(link.sources.count == count)
        #expect(link.capabilities == MixerCapabilities(usbChannelCount: 18, nameableUSBChannelCount: 18))
        #expect(link.identity?.model == "XR18")
    }

    @Test("With nothing Armed yet, reads as many Sources as the identified Mixer sends")
    func nothingArmedReadsMixerCount() async throws {
        let mixer = try await FakeXAirMixer()
        let link = MixerLinkController()

        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 0)

        #expect(link.sources.count == 18)
    }

    @Test("When the Armed device changes, Sources are re-read for its USB Channel count")
    func refreshForNewCount() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1)
        let mixer = try await FakeXAirMixer(state)
        let link = MixerLinkController()
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)

        await link.refreshSources(usbChannelCount: 8)

        #expect(link.sources.count == 8)
        #expect(link.sources[0].name == "Kick")
    }

    @Test("Re-reading Sources does nothing while the Link isn't up")
    func refreshWhileIdle() async {
        let link = MixerLinkController()

        await link.refreshSources(usbChannelCount: 8)

        #expect(link.status == .idle)
        #expect(link.sources.isEmpty)
        #expect(link.capabilities == nil)
    }

    @Test("A malformed address is rejected before anything is sent", arguments: ["10.0.0", "300.1.1.1", "", "mixer address"])
    func malformedAddressRejected(text: String) async {
        let link = MixerLinkController()

        await link.connect(to: text, usbChannelCount: 18)

        #expect(link.status == .down(.invalidAddress(text)))
        #expect(link.sources.isEmpty)
    }

    @Test("A Mixer that doesn't answer leaves the Link down with no reply")
    func silentMixerLeavesLinkDown() async throws {
        var state = FakeXAirMixer.State()
        state.answers = false
        let mixer = try await FakeXAirMixer(state)
        let link = MixerLinkController(timeout: .milliseconds(200))

        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)

        #expect(link.status == .down(.noReply(host: "127.0.0.1")))
    }

    @Test("Before connecting, the Link is idle")
    func idleBeforeConnecting() {
        #expect(MixerLinkController().status == .idle)
    }
}

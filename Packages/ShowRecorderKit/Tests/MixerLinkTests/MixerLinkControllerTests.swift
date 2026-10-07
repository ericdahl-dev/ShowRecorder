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

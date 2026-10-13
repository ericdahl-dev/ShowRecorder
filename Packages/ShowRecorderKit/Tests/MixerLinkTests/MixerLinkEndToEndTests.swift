import Foundation
import MixerLink
import Testing

/// The Mixer Link with its default driver over real loopback UDP, for what an in-memory driver can't show: the
/// connection itself coming back after the Mixer restarts.
@MainActor
@Suite("Mixer Link end to end")
struct MixerLinkEndToEndTests {
    @Test("After the Mixer is switched off and on again, the Link comes back by itself with the Sources read again")
    func powerCycle() async throws {
        var state = FakeXAirMixer.State()
        state.channels[0] = .init(name: "Kick", color: 1)
        state.usbRouting = XAirDriverTests.defaultRouting   // answered, so no read waits out its timeout
        let mixer = try await FakeXAirMixer(state)
        let link = MixerLinkController(timeout: .milliseconds(500), renewEvery: .milliseconds(100))
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)
        #expect(link.sources[safe: 0]?.name == "Kick")

        mixer.powerOff()
        #expect(await eventually(10) { if case .down = link.status { true } else { false } })
        mixer.update { $0.channels[0].name = "Bass Drum" }
        try await mixer.powerOn()

        #expect(await eventually(10) { link.sources[safe: 0]?.name == "Bass Drum" })
        mixer.rename(channel: 2, to: "Snare")
        #expect(await eventually(10) { link.sources[safe: 1]?.name == "Snare" })
    }
}

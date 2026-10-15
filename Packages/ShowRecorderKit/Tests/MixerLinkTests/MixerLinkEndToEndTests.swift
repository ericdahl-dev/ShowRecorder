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
        // Connecting asks the Mixer about 100 things one after another; each must answer in time even on a busy Mac,
        // or the Link never comes up and every wait below runs out (#464). Noticing the power-off takes one timeout.
        let link = MixerLinkController(timeout: Loopback.mixedTimeout, renewEvery: .milliseconds(100))
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)
        #expect(link.sources[safe: 0]?.name == "Kick")

        mixer.powerOff()
        #expect(await eventually(30) { if case .down = link.status { true } else { false } })
        mixer.update { $0.channels[0].name = "Bass Drum" }
        try await mixer.powerOn()

        #expect(await eventually(30) { link.sources[safe: 0]?.name == "Bass Drum" })
        mixer.rename(channel: 2, to: "Snare")
        #expect(await eventually(30) { link.sources[safe: 1]?.name == "Snare" })
    }
}

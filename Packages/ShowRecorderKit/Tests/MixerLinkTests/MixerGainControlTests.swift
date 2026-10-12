import Foundation
import MixerLink
import Testing

/// Mixer Link offers gain control for auto-gain (#155) when the linked Mixer's driver can set gain.
@MainActor
@Suite("Mixer gain control")
struct MixerGainControlTests {
    @Test("A linked X32 offers gain control, mapped from its USB routing")
    func x32() async throws {
        let mixer = try await FakeXAirMixer(.x32())
        let link = MixerLinkController()
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 32)

        let control = try #require(link.gainControl)
        #expect(control.channel(forUSBChannel: 5) == 5)
    }

    @Test("A linked XR18 offers gain control too (#153); no link offers none")
    func xr18AndIdle() async throws {
        let link = MixerLinkController()
        #expect(link.gainControl == nil)
        var state = FakeXAirMixer.State()
        state.usbRouting = (0..<18).map { [Int32($0), 0] }
        let mixer = try await FakeXAirMixer(state)
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)
        #expect(link.identity?.model == "XR18")
        let control = try #require(link.gainControl)
        #expect(control.channel(forUSBChannel: 5) == 5)
        #expect(control.channel(forUSBChannel: 17) == nil, "the aux return has no preamp")
    }
}

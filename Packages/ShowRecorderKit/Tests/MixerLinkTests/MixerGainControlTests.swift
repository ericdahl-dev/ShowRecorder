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
        let link = MixerLinkController(timeout: Loopback.replyTimeout)
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 32)

        let control = try #require(link.gainControl, "the Link is \(link.status)")
        #expect(control.channel(forUSBChannel: 5) == 5)
    }

    @Test("A linked XR18 offers gain control too (#153); no link offers none")
    func xr18AndIdle() async throws {
        let link = MixerLinkController(timeout: Loopback.replyTimeout)
        #expect(link.gainControl == nil)
        var state = FakeXAirMixer.State()
        state.usbRouting = (0..<18).map { [Int32($0), 0] }
        let mixer = try await FakeXAirMixer(state)
        await link.connect(to: "127.0.0.1:\(mixer.port)", usbChannelCount: 18)
        #expect(link.identity?.model == "XR18", "the Link is \(link.status)")
        let control = try #require(link.gainControl, "the Link is \(link.status)")
        #expect(control.channel(forUSBChannel: 5) == 5)
        #expect(control.channel(forUSBChannel: 17) == nil, "the aux return has no preamp")
    }

    @Test("The Link finds gain control on whichever driver it has, not only the ones it knows by type (#442)")
    func fromAnyDriver() async {
        let driver = FakeMixerDriver(gainControl: StubGainControl())
        let link = MixerLinkController(makeDriver: { _, _ in driver })
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)
        #expect(link.gainControl?.channel(forUSBChannel: 3) == 3)
    }

    @Test("A driver that can't set gain offers none, and a Link that went down offers none")
    func noneWithoutGain() async {
        let driver = FakeMixerDriver()
        let link = MixerLinkController(makeDriver: { _, _ in driver })
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)
        #expect(link.identity != nil)
        #expect(link.gainControl == nil)
    }
}

import AutoGain
import Foundation
import MixerLink
import Telemetry
import Testing

/// Usage events from the Mixer Link (ADR 0007, #1026): mixer_link_connected once per connection, with the Mixer
/// family only, never when the Link's own renewals bring a dropped Link back up.
@MainActor
@Suite("Mixer Link telemetry")
struct MixerLinkTelemetryTests {
    func session(_ driver: FakeMixerDriver, sent: @escaping (TelemetryEvent) -> Void) -> MixerSession {
        let link = MixerLinkController(renewEvery: .milliseconds(10), makeDriver: { _, _ in driver })
        let store = UserDefaults(suiteName: "MixerLinkTelemetryTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store)
        session.sendEvent = sent
        return session
    }

    @Test("Connecting sends mixer_link_connected once, with the Mixer family and nothing about its name")
    func connectedOnce() async {
        var sent: [TelemetryEvent] = []
        let session = session(FakeMixerDriver()) { sent.append($0) }
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        #expect(sent == [.mixerLinkConnected(mixerFamily: "xAir")])
        #expect(TelemetryEvent.mixerLinkConnected(mixerFamily: "xAir").properties == ["mixer_family": .string("xAir")])
    }

    @Test("An X32 is sent as its family")
    func x32() async {
        var state = FakeMixerDriver.State()
        state.identity = MixerIdentity(networkName: "FOH", model: "X32", firmware: "4.06")
        var sent: [TelemetryEvent] = []
        let session = session(FakeMixerDriver(state)) { sent.append($0) }
        await session.ready(interfaceName: "X-USB", usbChannelCount: 32)
        #expect(sent == [.mixerLinkConnected(mixerFamily: "x32")])
    }

    @Test("A Link that drops and comes back on its own renewals sends nothing more")
    func renewalsDontCount() async {
        let driver = FakeMixerDriver()
        var sent: [TelemetryEvent] = []
        let session = session(driver) { sent.append($0) }
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        driver.state.withLock { $0.problem = .networkUnreachable }
        #expect(await eventually { session.status == .down(.networkUnreachable) })
        driver.state.withLock { $0.problem = nil }
        #expect(await eventually { session.identity != nil })

        #expect(sent == [.mixerLinkConnected(mixerFamily: "xAir")])
    }

    @Test("Connecting again on purpose is a new connection; a connect that fails sends nothing")
    func eachConnection() async {
        let driver = FakeMixerDriver()
        var sent: [TelemetryEvent] = []
        let session = session(driver) { sent.append($0) }
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        await session.connect()
        driver.state.withLock { $0.problem = .networkUnreachable }
        await session.connect()
        #expect(sent == [.mixerLinkConnected(mixerFamily: "xAir"), .mixerLinkConnected(mixerFamily: "xAir")])
    }
}

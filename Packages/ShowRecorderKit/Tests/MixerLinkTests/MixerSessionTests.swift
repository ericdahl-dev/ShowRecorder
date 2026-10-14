import AutoGain
import Foundation
import MixerLink
import Testing

/// The Mixer session (#556): whether Mixer Link is offered for the Armed input, and when it connects, decided in one
/// place instead of across the app.
@MainActor
@Suite("Mixer session")
struct MixerSessionTests {
    /// A session on a Link to `driver`'s Mixer, remembering its address in a store of its own.
    func session(
        _ driver: FakeMixerDriver = FakeMixerDriver(gainControl: StubGainControl()), remembering address: String? = nil
    ) -> (MixerSession, MixerLinkController) {
        let link = MixerLinkController(makeDriver: { _, _ in driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        if let address { store.set(address, forKey: "mixerAddress") }
        return (MixerSession(link: link, store: store), link)
    }

    @Test("With another input Armed, there's no status, no Sources and no gain control, though the Link is still up")
    func otherInputHidesTheLink() async {
        let (session, link) = session()
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)
        #expect(session.gainControl != nil)

        await session.armed(interfaceName: "EVO 4", usbChannelCount: 2)

        #expect(session.gainControl == nil, "a stale Link must not move a Mixer's gain")
        #expect(session.status == nil)
        #expect(session.sources.isEmpty)
        #expect(link.identity != nil, "the Link stays up, hidden")
    }

    @Test("The Mixer's identity and what it sends over USB show while Mixer Link is offered, and hide with another input Armed")
    func identityAndCapabilitiesGated() async {
        let (session, link) = session()
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)
        #expect(session.identity?.networkName == "FOH")
        #expect(session.capabilities?.usbChannelCount == 18)

        await session.armed(interfaceName: "EVO 4", usbChannelCount: 2)

        #expect(session.identity == nil)
        #expect(session.capabilities == nil)
    }

    @Test("A remembered Mixer connects when an X Air is Armed and the Link is idle")
    func rememberedMixerConnectsOnArm() async {
        let driver = FakeMixerDriver()
        let (session, link) = session(driver, remembering: "10.0.0.20")

        await session.armed(interfaceName: "XR18", usbChannelCount: 18)

        #expect(link.status == .up(driver.state.withLock { $0.identity }, path: .wifi))
        #expect(session.sources.count == 18)
    }

    @Test("Arming again doesn't reconnect a Link that is down")
    func armAgainLeavesLink() async {
        let made = Counter()
        var state = FakeMixerDriver.State()
        state.problem = .noReply(host: "10.0.0.20")
        let down = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in made.increment(); return down })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store)

        await session.armed(interfaceName: "XR18", usbChannelCount: 18)
        guard case .down = link.status else { Issue.record("the Link should be down: \(link.status)"); return }
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)

        #expect(made.value == 1, "connected once, not again over a Link that's down")
    }

    @Test("Retry connects only when the Link is down, never over one that's up")
    func retryOnlyWhenDown() async {
        let made = Counter()
        let driver = FakeMixerDriver()
        let link = MixerLinkController(makeDriver: { _, _ in made.increment(); return driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store)
        driver.state.withLock { $0.problem = .noReply(host: "10.0.0.20") }
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)
        driver.state.withLock { $0.problem = nil }

        await session.retry()
        #expect(link.identity != nil, "a Link that was down is connected again")
        await session.retry()

        #expect(made.value == 2, "once at Arm, once to retry the Link that was down, and not over the one that's up")
    }

    @Test("Connect from Settings connects at the address typed, even when the Link is up")
    func connectFromSettings() async {
        let endpoints = Endpoints()
        let driver = FakeMixerDriver()
        let link = MixerLinkController(makeDriver: { endpoint, _ in endpoints.add(endpoint); return driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store)
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)
        #expect(link.identity != nil)

        session.address = "10.0.0.30"
        await session.connect()

        #expect(endpoints.hosts == ["10.0.0.20", "10.0.0.30"])
        #expect(store.string(forKey: "mixerAddress") == "10.0.0.30", "the address typed is remembered")
    }

    final class Endpoints: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [MixerEndpoint] = []
        func add(_ endpoint: MixerEndpoint) { lock.withLock { all.append(endpoint) } }
        var hosts: [String] { lock.withLock { all.map(\.host) } }
    }

    @Test("A Template's Mixer is connected at its saved address, which is remembered")
    func templateMixerAtAddress() async {
        let endpoints = Endpoints()
        let driver = FakeMixerDriver()
        let link = MixerLinkController(makeDriver: { endpoint, _ in endpoints.add(endpoint); return driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        let session = MixerSession(link: link, store: store)
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)

        await session.follow(mixerAt: "10.0.0.40", named: nil)

        #expect(endpoints.hosts == ["10.0.0.40"])
        #expect(link.identity != nil)
        #expect(session.address == "10.0.0.40")
    }

    @Test("A Template's Mixer that answers at its address under another name is looked for by name among the Mixers that answer, and that address remembered")
    func templateMixerByName() async {
        let endpoints = Endpoints()
        var mon = FakeMixerDriver.State()
        mon.identity = MixerIdentity(networkName: "MON", model: "XR18", firmware: "1.22")
        let bandName = MixerIdentity(networkName: "BAND", model: "XR18", firmware: "1.22")
        var band = FakeMixerDriver.State()
        band.identity = bandName
        let drivers = ["10.0.0.40": FakeMixerDriver(mon), "10.0.0.41": FakeMixerDriver(), "10.0.0.42": FakeMixerDriver(band)]  // .41 is "FOH"
        let link = MixerLinkController(makeDriver: { endpoint, _ in endpoints.add(endpoint); return drivers[endpoint.host]! })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        let foh = MixerIdentity(networkName: "FOH", model: "XR18", firmware: "1.22")
        let session = MixerSession(
            link: link, store: store, network: { ScanRange(address: "10.0.0.2", netmask: "255.255.255.0") },
            scan: { _ in [FoundMixer(host: "10.0.0.42", identity: bandName), FoundMixer(host: "10.0.0.41", identity: foh)] })
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)

        await session.follow(mixerAt: "10.0.0.40", named: "FOH")

        #expect(endpoints.hosts == ["10.0.0.40", "10.0.0.41"])
        #expect(link.identity?.networkName == "FOH")
        #expect(session.address == "10.0.0.41")
    }

    @Test("A Template's Mixer isn't connected while Mixer Link isn't offered; the address stays as it was")
    func templateMixerNotOffered() async {
        let endpoints = Endpoints()
        let link = MixerLinkController(makeDriver: { endpoint, _ in endpoints.add(endpoint); return FakeMixerDriver() })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        let session = MixerSession(link: link, store: store)
        await session.armed(interfaceName: "EVO 4", usbChannelCount: 2)

        await session.follow(mixerAt: "10.0.0.40", named: "FOH")

        #expect(endpoints.hosts.isEmpty)
        #expect(session.address == "")
    }

    @Test("With no network to scan, a Template's Mixer by name stays at its address")
    func templateMixerNoNetwork() async {
        let endpoints = Endpoints()
        var mon = FakeMixerDriver.State()
        mon.identity = MixerIdentity(networkName: "MON", model: "XR18", firmware: "1.22")
        let driver = FakeMixerDriver(mon)
        let link = MixerLinkController(makeDriver: { endpoint, _ in endpoints.add(endpoint); return driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        let session = MixerSession(link: link, store: store, network: { nil }, scan: { _ in
            Issue.record("nothing to scan")
            return []
        })
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)

        await session.follow(mixerAt: "10.0.0.40", named: "FOH")

        #expect(endpoints.hosts == ["10.0.0.40"])
        #expect(session.address == "10.0.0.40")
    }

    @Test("A new USB Channel count from the same Mixer re-reads its Sources, without connecting again")
    func newCountRereadsSources() async {
        let made = Counter()
        let driver = FakeMixerDriver()
        let link = MixerLinkController(makeDriver: { _, _ in made.increment(); return driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store)
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)

        await session.armed(interfaceName: "XR18", usbChannelCount: 12)

        #expect(session.sources.count == 12)
        #expect(made.value == 1)
    }

    @Test("A new USB Channel count while the Link is still connecting is the count its Sources are read with")
    func newCountWhileConnecting() async {
        var state = FakeMixerDriver.State()
        state.holdsIdentify = true
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store)

        let arming = Task { await session.armed(interfaceName: "XR18", usbChannelCount: 18) }
        while link.status == .idle { await Task.yield() }
        await session.armed(interfaceName: "XR18", usbChannelCount: 12)
        driver.releaseIdentify()
        await arming.value

        #expect(session.sources.count == 12)
    }

    @Test("Connect with no address tries anyway and says the address is invalid, as Settings always has")
    func connectWithNoAddress() async {
        let (session, link) = session()
        await session.armed(interfaceName: "XR18", usbChannelCount: 18)

        await session.connect()

        guard case .down = link.status else {
            Issue.record("expected the Link down with an invalid address, got \(link.status)")
            return
        }
    }

    @Test("At launch with nothing Armed, a remembered Mixer isn't connected")
    func launchWithNothingArmed() async {
        let made = Counter()
        let link = MixerLinkController(makeDriver: { _, _ in made.increment(); return FakeMixerDriver() })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store)

        await session.armed(interfaceName: nil, usbChannelCount: 0)

        #expect(made.value == 0)
        #expect(!session.isOffered)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }
}

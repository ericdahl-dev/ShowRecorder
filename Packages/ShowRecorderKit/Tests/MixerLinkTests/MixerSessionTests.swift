import AutoGain
import Foundation
import MixerLink
import Testing

/// The Mixer session (#556): whether Mixer Link is offered for the Ready input, and when it connects, decided in one
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
        return (MixerSession(link: link, store: store, network: { nil }, checksUSBMixer: { true }), link)
    }

    // MARK: Which Mixer is plugged in by USB (#1018)

    /// Two X Air mixers that answer on this network: the linked "FOH" at 10.0.0.20 and "MON" at 10.0.0.21.
    nonisolated static let twoXR18s = [
        FoundMixer(host: "10.0.0.20", identity: MixerIdentity(networkName: "FOH", model: "XR18", firmware: "1.22")),
        FoundMixer(host: "10.0.0.21", identity: MixerIdentity(networkName: "MON", model: "XR18", firmware: "1.22")),
    ]

    /// A session whose Find Mixers scan answers `found`, on a Link to `driver`'s Mixer at 10.0.0.20.
    /// With `checking` false, `USBMixerCheckAvailability` is off, as in the App Store build; `scans` counts the scans.
    func session(finding found: [FoundMixer], _ driver: FakeMixerDriver = FakeMixerDriver(gainControl: StubGainControl()),
                 checking: Bool = true, scans: Counter = Counter()) -> (MixerSession, MixerLinkController) {
        let link = MixerLinkController(makeDriver: { _, _ in driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store, network: { ScanRange(address: "10.0.0.2", netmask: "255.255.255.0") },
                                   scan: { _ in scans.increment(); return found }, checksUSBMixer: { checking })
        return (session, link)
    }

    // MARK: With the check off (USBMixerCheckAvailability, the App Store build), the Link is as it was before #1018.

    @Test("With the check off, two Mixers of the Ready family on the network still get the gain control at once, as before #1018")
    func twoOfTheFamilyOfferGainWhenCheckOff() async {
        let (session, _) = session(finding: Self.twoXR18s, checking: false)

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(session.gainControl != nil)
        #expect(session.usbMixerUnsure == nil, "so auto-gain gives no reason about other Mixers")
    }

    @Test("With the check off, a Link asks the network nothing")
    func noScanWhenCheckOff() async {
        let scans = Counter()
        let (session, link) = session(finding: Self.twoXR18s, checking: false, scans: scans)

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        await session.connect()

        #expect(link.identity != nil)
        #expect(scans.value == 0)
    }

    @Test("With the check off, Find Mixers doesn't ask for the USB Mixer, even with two of the Ready family")
    func findMixersAsksNothingWhenCheckOff() async {
        let (session, _) = session(finding: Self.twoXR18s, checking: false)
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(!session.asksForUSBMixer(among: Self.twoXR18s))
    }

    @Test("With two Mixers of the Ready family on the network and none picked as the USB one, the gain control isn't offered, so auto-gain can't move either one's preamps (#1018)")
    func twoOfTheFamilyRefuseGain() async {
        let (session, link) = session(finding: Self.twoXR18s)

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(link.identity != nil, "the Link is up")
        #expect(session.gainControl == nil, "MON may be the Mixer plugged in by USB, not FOH")
    }

    @Test("With the linked Mixer the only one of its family on the network, the gain control is offered, as before (#1018)")
    func onlyOneOfTheFamilyOffersGain() async {
        let (session, _) = session(finding: [Self.twoXR18s[0]])

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(session.usbMixerCheck == .onlyOne)
        #expect(session.gainControl != nil)
    }

    @Test("A Mixer of another family on the network doesn't count: an X32 next to the linked XR18 leaves the gain control offered (#1018)")
    func otherFamilyDoesNotCount() async {
        let x32 = FoundMixer(host: "10.0.0.30", identity: MixerIdentity(networkName: "MAIN", model: "X32", firmware: "4.06"))
        let (session, _) = session(finding: [Self.twoXR18s[0], x32])

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(session.gainControl != nil)
    }

    @Test("The linked Mixer counts even when its own reply to the scan is lost: one other XR18 answering makes two (#1018)")
    func linkedMixerCountsWithoutItsReply() async {
        let (session, _) = session(finding: [Self.twoXR18s[1]])

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(session.usbMixerCheck == .several(Self.twoXR18s))
        #expect(session.gainControl == nil)
    }

    @Test("Picking the linked Mixer in Find Mixers as the one plugged in by USB offers its gain control, with another of its family on the network (#1018)")
    func pickedUSBMixerOffersGain() async {
        let (session, _) = session(finding: Self.twoXR18s)
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        #expect(session.gainControl == nil)

        await session.connect(toUSBMixer: Self.twoXR18s[0])

        #expect(session.gainControl != nil)
        #expect(session.address == "10.0.0.20")
    }

    @Test("The Mixer picked as the USB one stays picked over a reconnect, and a Link to another Mixer isn't (#1018)")
    func pickedUSBMixerIsThatMixerOnly() async {
        var mon = FakeMixerDriver.State()
        mon.identity = Self.twoXR18s[1].identity
        let drivers = ["10.0.0.20": FakeMixerDriver(gainControl: StubGainControl()), "10.0.0.21": FakeMixerDriver(mon, gainControl: StubGainControl())]
        let link = MixerLinkController(makeDriver: { endpoint, _ in drivers[endpoint.host]! })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        let session = MixerSession(link: link, store: store, network: { ScanRange(address: "10.0.0.2", netmask: "255.255.255.0") },
                                   scan: { _ in Self.twoXR18s }, checksUSBMixer: { true })
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        await session.connect(toUSBMixer: Self.twoXR18s[0])

        await session.connect()
        #expect(session.gainControl != nil, "FOH again, still the one picked")

        session.address = "10.0.0.21"
        await session.connect()
        #expect(link.identity?.networkName == "MON")
        #expect(session.gainControl == nil, "MON wasn't picked")
    }

    @Test("While the network is still being asked, the gain control isn't offered (#1018)")
    func noGainWhileChecking() async {
        let gate = AsyncStream<Void>.makeStream()
        let asked = Counter()
        let driver = FakeMixerDriver(gainControl: StubGainControl())
        let link = MixerLinkController(makeDriver: { _, _ in driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store, network: { ScanRange(address: "10.0.0.2", netmask: "255.255.255.0") },
                                   scan: { _ in
                                       asked.increment()
                                       for await _ in gate.stream { break }
                                       return [Self.twoXR18s[0]]
                                   }, checksUSBMixer: { true })

        let gettingReady = Task { await session.ready(interfaceName: "XR18", usbChannelCount: 18) }
        let scanning = await eventually { asked.value == 1 }
        #expect(scanning, "the session asks the network once the Link is up")
        #expect(link.identity != nil)
        #expect(session.usbMixerCheck == .checking)
        #expect(session.gainControl == nil)
        // Bounded either way: finishing the stream ends the scan's wait even if the yield is missed.
        gate.continuation.yield()
        gate.continuation.finish()
        await gettingReady.value

        #expect(session.gainControl != nil)
    }

    @Test("A Link made around the session, never checked, offers no gain control (#1018)")
    func uncheckedLinkOffersNoGain() async {
        let (session, link) = session()
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        #expect(session.gainControl == nil)
    }

    @Test("Find Mixers asks for the USB one only when more than one Mixer of the Ready family answers (#1018)")
    func findMixersAsksForUSBMixer() async {
        let (session, _) = session()
        let x32 = FoundMixer(host: "10.0.0.30", identity: MixerIdentity(networkName: "MAIN", model: "X32", firmware: "4.06"))
        #expect(!session.asksForUSBMixer(among: Self.twoXR18s), "nothing Ready")

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(session.asksForUSBMixer(among: Self.twoXR18s))
        #expect(!session.asksForUSBMixer(among: [Self.twoXR18s[0], x32]), "one X Air and an X32")
        await session.ready(interfaceName: "X-USB", usbChannelCount: 32)
        #expect(!session.asksForUSBMixer(among: Self.twoXR18s), "two X Airs, but an X32 Ready")
    }

    @Test("Tapping a Mixer in Find Mixers picks it as the USB one when Find Mixers asked, and only links it otherwise (#1018)")
    func findMixersTapPicksWhenAsked() async {
        var mon = FakeMixerDriver.State()
        mon.identity = Self.twoXR18s[1].identity
        let drivers = ["10.0.0.20": FakeMixerDriver(gainControl: StubGainControl()), "10.0.0.21": FakeMixerDriver(mon, gainControl: StubGainControl())]
        let link = MixerLinkController(makeDriver: { endpoint, _ in drivers[endpoint.host]! })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        let session = MixerSession(link: link, store: store, network: { ScanRange(address: "10.0.0.2", netmask: "255.255.255.0") },
                                   scan: { _ in Self.twoXR18s }, checksUSBMixer: { true })
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        await session.choose(Self.twoXR18s[1], among: [Self.twoXR18s[1]])
        #expect(link.identity?.networkName == "MON")
        #expect(session.gainControl == nil, "Find Mixers listed one, so the tap only linked it; the check still finds two")

        await session.choose(Self.twoXR18s[1], among: Self.twoXR18s)
        #expect(session.address == "10.0.0.21")
        #expect(session.gainControl != nil, "picked as the USB one")
    }

    @Test("With another input Ready, there's no status, no Sources and no gain control, though the Link is still up")
    func otherInputHidesTheLink() async {
        let (session, link) = session()
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        session.address = "10.0.0.20"
        await session.connect()
        #expect(session.gainControl != nil)

        await session.ready(interfaceName: "EVO 4", usbChannelCount: 2)

        #expect(session.gainControl == nil, "a stale Link must not move a Mixer's gain")
        #expect(session.status == nil)
        #expect(session.sources.isEmpty)
        #expect(link.identity != nil, "the Link stays up, hidden")
    }

    @Test("With an X32 Ready while the Link is still on an XR18, nothing of the XR18 is used: no gain control, Sources, identity or capabilities (#589)")
    func otherMixerFamilyHidesTheLinkedMixer() async {
        let (session, _) = session()
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        session.address = "10.0.0.20"
        await session.connect()
        #expect(session.gainControl != nil)

        await session.ready(interfaceName: "X-USB", usbChannelCount: 32)

        #expect(session.isOffered, "Settings still offers connecting to the X32")
        #expect(session.status != nil, "Settings shows where the Link is")
        #expect(session.gainControl == nil, "the XR18's preamps must not move for the X32's audio")
        #expect(session.sources.isEmpty)
        #expect(session.identity == nil)
        #expect(session.capabilities == nil)
    }

    @Test("With an X32 Ready while the Link is still on an XR18, the session names the XR18 as the other Mixer linked (#647)")
    func otherMixerLinkedNamesTheLinkedMixer() async {
        let driver = FakeMixerDriver(gainControl: StubGainControl())
        let (session, link) = session(driver)
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)
        #expect(session.otherMixerLinked == nil, "the linked Mixer is the Ready family")

        await session.ready(interfaceName: "X-USB", usbChannelCount: 32)
        #expect(session.otherMixerLinked?.networkName == "FOH")
        #expect(session.otherMixerLinked?.model == "XR18")

        driver.state.withLock { $0.problem = .noReply(host: "10.0.0.20") }
        await link.connect(to: "10.0.0.20", usbChannelCount: 32)
        guard case .down = link.status else { Issue.record("the Link should be down: \(link.status)"); return }
        #expect(session.otherMixerLinked == nil, "a Link that's down is on no Mixer")
        driver.state.withLock { $0.problem = nil }
        await link.connect(to: "10.0.0.20", usbChannelCount: 32)

        await session.ready(interfaceName: "EVO 4", usbChannelCount: 2)
        #expect(session.otherMixerLinked == nil, "Mixer Link isn't offered")
    }

    @Test("The session's Mixer state: nil while not offered, not linked when idle, linked on the Ready family, the other Mixer on another family, down with its problem (#556)")
    func mixerState() async {
        let driver = FakeMixerDriver(gainControl: StubGainControl())
        let (session, link) = session(driver)
        #expect(session.state == nil, "Mixer Link isn't offered")

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        #expect(session.state == .notLinked)

        await link.connect(to: "10.0.0.20", usbChannelCount: 18)
        let identity = driver.state.withLock { $0.identity }
        #expect(session.state == .linked(identity, path: .wifi))

        await session.ready(interfaceName: "X-USB", usbChannelCount: 32)
        #expect(session.state == .otherMixer(identity))

        driver.state.withLock { $0.problem = .noReply(host: "10.0.0.20") }
        await link.connect(to: "10.0.0.20", usbChannelCount: 32)
        #expect(session.state == .down(.noReply(host: "10.0.0.20")))

        await session.ready(interfaceName: "EVO 4", usbChannelCount: 2)
        #expect(session.state == nil, "Mixer Link isn't offered")
    }

    @Test("The Mixer's identity and what it sends over USB show while Mixer Link is offered, and hide with another input Ready")
    func identityAndCapabilitiesGated() async {
        let (session, _) = session()
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        session.address = "10.0.0.20"
        await session.connect()
        #expect(session.identity?.networkName == "FOH")
        #expect(session.capabilities?.usbChannelCount == 18)

        await session.ready(interfaceName: "EVO 4", usbChannelCount: 2)

        #expect(session.identity == nil)
        #expect(session.capabilities == nil)

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(session.gainControl != nil, "the XR18 Ready again is the linked Mixer again")
        #expect(session.identity?.model == "XR18")
    }

    @Test("The linked Mixer's network name is still there for a Template while nothing is Ready")
    func networkNameForTemplates() async {
        let (session, link) = session()
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        await session.ready(interfaceName: nil, usbChannelCount: 0)

        #expect(session.identity == nil)
        #expect(session.networkNameForTemplates == "FOH")
    }

    @Test("A remembered Mixer connects when an X Air is Ready and the Link is idle")
    func rememberedMixerConnectsOnGetReady() async {
        let driver = FakeMixerDriver()
        let (session, link) = session(driver, remembering: "10.0.0.20")

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(link.status == .up(driver.state.withLock { $0.identity }, path: .wifi))
        #expect(session.sources.count == 18)
    }

    @Test("Getting ready again doesn't reconnect a Link that is down")
    func getReadyAgainLeavesLink() async {
        let made = Counter()
        var state = FakeMixerDriver.State()
        state.problem = .noReply(host: "10.0.0.20")
        let down = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in made.increment(); return down })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store, network: { nil })

        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        guard case .down = link.status else { Issue.record("the Link should be down: \(link.status)"); return }
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        #expect(made.value == 1, "connected once, not again over a Link that's down")
    }

    @Test("Retry connects only when the Link is down, never over one that's up")
    func retryOnlyWhenDown() async {
        let made = Counter()
        let driver = FakeMixerDriver()
        let link = MixerLinkController(makeDriver: { _, _ in made.increment(); return driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store, network: { nil })
        driver.state.withLock { $0.problem = .noReply(host: "10.0.0.20") }
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
        driver.state.withLock { $0.problem = nil }

        await session.retry()
        #expect(link.identity != nil, "a Link that was down is connected again")
        await session.retry()

        #expect(made.value == 2, "once when getting ready, once to retry the Link that was down, and not over the one that's up")
    }

    @Test("Connect from Settings connects at the address typed, even when the Link is up")
    func connectFromSettings() async {
        let endpoints = Endpoints()
        let driver = FakeMixerDriver()
        let link = MixerLinkController(makeDriver: { endpoint, _ in endpoints.add(endpoint); return driver })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store, network: { nil })
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)
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
        let session = MixerSession(link: link, store: store, network: { nil })
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

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
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

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
        let session = MixerSession(link: link, store: store, network: { nil })
        await session.ready(interfaceName: "EVO 4", usbChannelCount: 2)

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
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

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
        let session = MixerSession(link: link, store: store, network: { nil })
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        await session.ready(interfaceName: "XR18", usbChannelCount: 12)

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
        let session = MixerSession(link: link, store: store, network: { nil })

        let gettingReady = Task { await session.ready(interfaceName: "XR18", usbChannelCount: 18) }
        while link.status == .idle { await Task.yield() }
        #expect(session.state == .connecting(host: "10.0.0.20"))
        await session.ready(interfaceName: "XR18", usbChannelCount: 12)
        driver.releaseIdentify()
        await gettingReady.value

        #expect(session.sources.count == 12)
    }

    @Test("Connect with no address tries anyway and says the address is invalid, as Settings always has")
    func connectWithNoAddress() async {
        let (session, link) = session()
        await session.ready(interfaceName: "XR18", usbChannelCount: 18)

        await session.connect()

        guard case .down = link.status else {
            Issue.record("expected the Link down with an invalid address, got \(link.status)")
            return
        }
    }

    @Test("At launch with nothing Ready, a remembered Mixer isn't connected")
    func launchWithNothingReady() async {
        let made = Counter()
        let link = MixerLinkController(makeDriver: { _, _ in made.increment(); return FakeMixerDriver() })
        let store = UserDefaults(suiteName: "MixerSessionTests-\(UUID().uuidString)")!
        store.set("10.0.0.20", forKey: "mixerAddress")
        let session = MixerSession(link: link, store: store, network: { nil })

        await session.ready(interfaceName: nil, usbChannelCount: 0)

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

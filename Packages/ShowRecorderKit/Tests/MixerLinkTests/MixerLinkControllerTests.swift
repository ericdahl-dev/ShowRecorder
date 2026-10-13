import MixerLink
import Synchronization
import Testing

/// The Mixer Link controller against an in-memory Mixer driver (#442): what it does with what a driver answers. What
/// each Mixer family's driver answers is in its own suite, and `MixerGainControlTests` connects the default Link to a
/// fake X-Air and a fake X32 over UDP.
@MainActor
@Suite("Mixer Link controller")
struct MixerLinkControllerTests {
    @Test("Connecting to a Mixer's address brings the Link up over Wi-Fi with its Sources")
    func connectBringsLinkUp() async {
        var state = FakeMixerDriver.State()
        state.names[2] = "Snare"
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        #expect(link.status == .up(state.identity, path: .wifi))
        #expect(link.sources.count == 18)
        #expect(link.sources[safe: 1]?.name == "Snare")
        #expect(link.sources[safe: 0]?.name == "USB 01")
    }

    @Test("The driver is made for the address typed in, port included")
    func driverForTypedAddress() async {
        let endpoints = Mutex<[MixerEndpoint]>([])
        let driver = FakeMixerDriver()
        let link = MixerLinkController(makeDriver: { endpoint, _ in
            endpoints.withLock { $0.append(endpoint) }
            return driver
        })

        await link.connect(to: "10.0.0.20:10023", usbChannelCount: 18)

        #expect(endpoints.withLock { $0 } == [MixerEndpoint(host: "10.0.0.20", port: 10023)])
    }

    @Test("Reads one Source per USB Channel the Armed device sends; those the driver can't name are USB NN", arguments: [8, 16, 18, 32])
    func readsSourcesForArmedCount(count: Int) async {
        var state = FakeMixerDriver.State()
        state.capabilities = MixerCapabilities(usbChannelCount: 18, nameableUSBChannelCount: 16)
        state.names[1] = "Kick"
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        await link.connect(to: "10.0.0.20", usbChannelCount: count)

        #expect(link.sources.count == count)
        #expect(link.sources[safe: 0]?.name == "Kick")
        #expect(driver.state.withLock { $0.sourceReads } == [min(count, 16)])
        #expect(Array(link.sources.dropFirst(16)) == stride(from: 17, through: count, by: 1).map { Source.fallback(usbChannel: $0) })
        #expect(link.capabilities == state.capabilities)
        #expect(link.identity == state.identity)
    }

    @Test("With nothing Armed yet, reads as many Sources as the identified Mixer sends")
    func nothingArmedReadsMixerCount() async {
        var state = FakeMixerDriver.State()
        state.capabilities = MixerCapabilities(usbChannelCount: 18, nameableUSBChannelCount: 18)
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        await link.connect(to: "10.0.0.20", usbChannelCount: 0)

        #expect(link.sources.count == 18)
        #expect(driver.state.withLock { $0.sourceReads } == [18])
    }

    @Test("When the Armed device changes, Sources are re-read for its USB Channel count")
    func refreshForNewCount() async {
        var state = FakeMixerDriver.State()
        state.names[1] = "Kick"
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })
        await link.connect(to: "10.0.0.20", usbChannelCount: 16)

        await link.refreshSources(usbChannelCount: 8)

        #expect(link.sources.count == 8)
        #expect(link.sources[safe: 0]?.name == "Kick")
        #expect(driver.state.withLock { $0.sourceReads } == [16, 8])
    }

    @Test("A device Armed while the Link is still connecting gets Sources for its own count")
    func refreshDuringConnect() async {
        var state = FakeMixerDriver.State()
        state.capabilities = MixerCapabilities(usbChannelCount: 18, nameableUSBChannelCount: 18)
        state.holdsIdentify = true
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        let connecting = Task { await link.connect(to: "10.0.0.20", usbChannelCount: 0) }
        #expect(await eventually { link.status == .connecting(host: "10.0.0.20") })
        await link.refreshSources(usbChannelCount: 8)
        driver.releaseIdentify()
        await connecting.value

        #expect(link.sources.count == 8)
        #expect(driver.state.withLock { $0.sourceReads } == [18, 8])
    }

    @Test("A Mixer with no multichannel USB names none of the device's USB Channels")
    func mixerWithoutUSBNamesNothing() async {
        var state = FakeMixerDriver.State()
        state.identity = MixerIdentity(networkName: "FOH", model: "XR16", firmware: "1.22")
        state.capabilities = MixerCapabilities(usbChannelCount: nil, nameableUSBChannelCount: 0)
        state.names[1] = "Kick"
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        await link.connect(to: "10.0.0.20", usbChannelCount: 8)

        #expect(link.sources == (1...8).map { Source.fallback(usbChannel: $0) })
        #expect(driver.state.withLock { $0.sourceReads } == [0])
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
        let driversMade = Mutex(0)
        let link = MixerLinkController(makeDriver: { _, _ in
            driversMade.withLock { $0 += 1 }
            return FakeMixerDriver()
        })

        await link.connect(to: text, usbChannelCount: 18)

        #expect(link.status == .down(.invalidAddress(text)))
        #expect(link.sources.isEmpty)
        #expect(driversMade.withLock { $0 } == 0)
    }

    @Test("A Mixer that doesn't answer leaves the Link down with no reply")
    func silentMixerLeavesLinkDown() async {
        var state = FakeMixerDriver.State()
        state.problem = .noReply(host: "10.0.0.20")
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        #expect(link.status == .down(.noReply(host: "10.0.0.20")))
        #expect(link.sources.isEmpty)
        #expect(link.capabilities == nil)
    }

    @Test("Before connecting, the Link is idle")
    func idleBeforeConnecting() {
        #expect(MixerLinkController().status == .idle)
    }
}

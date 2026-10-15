import Foundation
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

    @Test("A busy port is a passing problem: connecting tries again, and the Link comes up (#655)")
    func busyPortRetried() async {
        let busy = MixerLinkProblem.cantConnect(host: "10.0.0.20", port: 10024, code: Int(EADDRINUSE))
        var state = FakeMixerDriver.State()
        state.failsIdentify = [busy, busy]
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        #expect(link.status == .up(state.identity, path: .wifi))
        #expect(driver.state.withLock { $0.identifies } == 3)
    }

    @Test("A port that stays busy leaves the Link down after a few tries (#655)")
    func busyPortGivesUp() async {
        let busy = MixerLinkProblem.cantConnect(host: "10.0.0.20", port: 10024, code: Int(EADDRINUSE))
        var state = FakeMixerDriver.State()
        state.problem = busy
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        #expect(link.status == .down(busy))
        #expect(driver.state.withLock { $0.identifies } == 3)
    }

    @Test("Problems other than a busy port take the Link down at once, without trying again (#655)", arguments: [
        MixerLinkProblem.noReply(host: "10.0.0.20"),
        MixerLinkProblem.cantConnect(host: "10.0.0.20", port: 10024, code: Int(ECONNABORTED)),
    ])
    func otherProblemsNotRetried(problem: MixerLinkProblem) async {
        var state = FakeMixerDriver.State()
        state.problem = problem
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        #expect(link.status == .down(problem))
        #expect(driver.state.withLock { $0.identifies } == 1)
    }

    @Test("A connect still trying a busy port doesn't overwrite a newer connect's Link when it ends (#655)", arguments: [false, true])
    func newerConnectWins(olderFails: Bool) async {
        var older = FakeMixerDriver.State()
        older.identity = MixerIdentity(networkName: "Old", model: "XR18", firmware: "1.22")
        older.failsIdentify = [.cantConnect(host: "10.0.0.20", port: 10024, code: Int(EADDRINUSE))]
        older.holdsIdentify = true
        var newer = FakeMixerDriver.State()
        newer.names[1] = "Kick"
        let olderDriver = FakeMixerDriver(older)
        let newerDriver = FakeMixerDriver(newer)
        let link = MixerLinkController(makeDriver: { endpoint, _ in endpoint.host == "10.0.0.20" ? olderDriver : newerDriver })

        let olderConnect = Task { await link.connect(to: "10.0.0.20", usbChannelCount: 18) }
        #expect(await eventually { olderDriver.state.withLock { $0.identifies } == 2 })
        await link.connect(to: "10.0.0.21", usbChannelCount: 18)
        #expect(link.status == .up(newer.identity, path: .wifi))
        if olderFails { olderDriver.state.withLock { $0.problem = .noReply(host: "10.0.0.20") } }
        olderDriver.releaseIdentify()
        await olderConnect.value

        #expect(link.status == .up(newer.identity, path: .wifi))
        #expect(link.sources.count == 18)
        #expect(link.sources[safe: 0]?.name == "Kick")
    }

    @Test("A connect canceled while waiting to try a busy port again leaves the Link down, not connecting (#655)")
    func canceledDuringRetryWait() async {
        let busy = MixerLinkProblem.cantConnect(host: "10.0.0.20", port: 10024, code: Int(EADDRINUSE))
        var state = FakeMixerDriver.State()
        state.problem = busy
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(retryDelay: .seconds(2), makeDriver: { _, _ in driver })

        let connecting = Task { await link.connect(to: "10.0.0.20", usbChannelCount: 18) }
        #expect(await eventually { driver.state.withLock { $0.identifies } == 1 })
        connecting.cancel()
        await connecting.value

        #expect(link.status == .down(busy))
        #expect(driver.state.withLock { $0.identifies } == 1)
    }

    @Test("A busy port, then no reply, leaves the Link down with no reply (#655)")
    func busyThenNoReply() async {
        var state = FakeMixerDriver.State()
        state.failsIdentify = [.cantConnect(host: "10.0.0.20", port: 10024, code: Int(EADDRINUSE))]
        state.problem = .noReply(host: "10.0.0.20")
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })

        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        #expect(link.status == .down(.noReply(host: "10.0.0.20")))
        #expect(driver.state.withLock { $0.identifies } == 2)
    }

    @Test("Before connecting, the Link is idle")
    func idleBeforeConnecting() {
        #expect(MixerLinkController().status == .idle)
    }
}

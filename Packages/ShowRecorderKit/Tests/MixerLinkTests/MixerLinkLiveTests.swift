import MixerLink
import Testing

/// Live updates through the Mixer Link controller, against an in-memory Mixer driver (#442). How each family's driver
/// turns what its Mixer pushes into Source changes is in `XAirDriverTests` and `X32DriverTests`.
@MainActor
@Suite("Mixer Link live updates")
struct MixerLinkLiveTests {
    @Test("A rename on the Mixer reaches the Sources while the Link is up")
    func renameShowsUp() async {
        var state = FakeMixerDriver.State()
        state.names[2] = "Snare"
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        driver.push(SourceChange(usbChannel: 2, name: "Snare Top"))

        #expect(await eventually { link.sources[safe: 1]?.name == "Snare Top" })
        #expect(link.sources[safe: 1]?.hasMixerName == true)
    }

    @Test("While the Link is up it keeps renewing the Mixer's live updates, so changes keep arriving")
    func keepsRenewing() async {
        let driver = FakeMixerDriver()
        let link = MixerLinkController(renewEvery: .milliseconds(10), makeDriver: { _, _ in driver })
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        #expect(await eventually { driver.state.withLock { $0.renewals } >= 4 })
        driver.push(SourceChange(usbChannel: 3, name: "Hat"))

        #expect(await eventually { link.sources[safe: 2]?.name == "Hat" })
        #expect(link.identity != nil)
    }

    @Test(
        "When the Mixer stops answering the Link goes down, and when it is back the Sources are read again, including renames it missed",
        arguments: [MixerLinkProblem.noReply(host: "10.0.0.20"), .networkUnreachable]
    )
    func lossAndResync(problem: MixerLinkProblem) async {
        var state = FakeMixerDriver.State()
        state.names[1] = "Kick"
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(renewEvery: .milliseconds(10), makeDriver: { _, _ in driver })
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)
        #expect(link.sources[safe: 0]?.name == "Kick")

        driver.state.withLock { $0.problem = problem }
        #expect(await eventually { link.status == .down(problem) })
        #expect(link.sources.isEmpty)
        driver.state.withLock { $0.names[1] = "Bass Drum" }  // renamed while nobody could hear it
        driver.state.withLock { $0.problem = nil }

        #expect(await eventually { link.identity != nil && link.sources.count == 18 })
        #expect(link.sources[safe: 0]?.name == "Bass Drum")
        #expect(driver.state.withLock { $0.sourceReads.last } == 16, "as many as before, up to what the driver names")
        driver.push(SourceChange(usbChannel: 2, name: "Snare"))  // and live updates work again
        #expect(await eventually { link.sources[safe: 1]?.name == "Snare" })
    }

    @Test("Color changes are applied, a cleared name goes back to the USB default, and each USB Channel takes its own change")
    func colorAndClearedName() async {
        var state = FakeMixerDriver.State()
        state.names[4] = "Tom"
        let driver = FakeMixerDriver(state)
        let link = MixerLinkController(makeDriver: { _, _ in driver })
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)

        driver.push(SourceChange(usbChannel: 4, color: MixerColor(hue: .green, inverted: true)))
        driver.push(SourceChange(usbChannel: 4, name: ""))
        driver.push(SourceChange(usbChannel: 17, name: "Playback"))
        driver.push(SourceChange(usbChannel: 18, name: "Playback"))
        driver.push(SourceChange(usbChannel: 19, name: "Beyond the device"))  // no such USB Channel: ignored

        #expect(await eventually { link.sources[safe: 16]?.name == "Playback" && link.sources[safe: 17]?.name == "Playback" })
        #expect(link.sources[safe: 3]?.name == "USB 04")
        #expect(link.sources[safe: 3]?.hasMixerName == false)
        #expect(link.sources[safe: 3]?.color == MixerColor(hue: .green, inverted: true))
        #expect(link.sources.count == 18)
    }

    @Test("A connect the Mixer doesn't answer keeps trying, and links once the Mixer answers (#1209)")
    func connectKeepsTrying() async {
        var state = FakeMixerDriver.State()
        state.names[1] = "Kick"
        state.problem = .noReply(host: "10.0.0.20")
        let driver = FakeMixerDriver(state)
        var connected = 0
        let link = MixerLinkController(renewEvery: .milliseconds(10), makeDriver: { _, _ in driver })
        link.onConnected = { _ in connected += 1 }
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)
        #expect(link.status == .down(.noReply(host: "10.0.0.20")))

        driver.state.withLock { $0.problem = nil }  // the Mixer is back on the network

        #expect(await eventually { link.identity != nil && link.sources.count == 18 })
        #expect(link.sources[safe: 0]?.name == "Kick")
        #expect(connected == 1, "a new connection, told once")
        driver.push(SourceChange(usbChannel: 2, name: "Snare"))  // and live updates work
        #expect(await eventually { link.sources[safe: 1]?.name == "Snare" })
    }

    @Test("A newer connect stops the retries of one the Mixer didn't answer (#1209)")
    func newerConnectStopsRetries() async {
        var silent = FakeMixerDriver.State()
        silent.problem = .noReply(host: "10.0.0.20")
        let old = FakeMixerDriver(silent)
        let new = FakeMixerDriver()
        let link = MixerLinkController(renewEvery: .milliseconds(10), makeDriver: { endpoint, _ in
            endpoint.host == "10.0.0.20" ? old : new
        })
        await link.connect(to: "10.0.0.20", usbChannelCount: 18)
        await link.connect(to: "10.0.0.21", usbChannelCount: 18)
        #expect(link.host == "10.0.0.21")

        old.state.withLock { $0.problem = nil }  // the first Mixer answers after all

        // Long enough for many retries at 10 ms.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(link.host == "10.0.0.21")
    }
}

import Foundation
import MixerLink
import OSC
import Testing

/// WING live updates (#417, Eric 2026-11-10): the driver re-reads the Sources every few seconds and sends what moved.
/// It never subscribes (`/*S`, `/*s`): a WING keeps one OSC subscriber, the last to ask, so subscribing would cut off
/// any other OSC app on the desk. Checked only against an in-memory fake WING.
@MainActor
@Suite("WING live updates")
struct WingLiveUpdatesTests {
    /// A WING with USB 1 on LCL 1 ("Kick", red) and USB 2 on A 5 ("Lead Vox", yellow).
    static func twoChannelWing() -> FakeWing.State {
        var state = FakeWing.State()
        for (usb, group, input) in [(1, "LCL", 1), (2, "A", 5)] {
            state.replies["/io/out/USB/\(usb)/grp"] = [.string(group)]
            state.replies["/io/out/USB/\(usb)/in"] = FakeWing.intReply(input)
        }
        state.replies["/io/in/LCL/1/name"] = [.string("Kick")]
        state.replies["/io/in/LCL/1/col"] = FakeWing.intReply(9)
        state.replies["/io/in/A/5/name"] = [.string("Lead Vox")]
        state.replies["/io/in/A/5/col"] = FakeWing.intReply(7)
        state.replies["/io/in/B/3/name"] = [.string("Bass DI")]
        state.replies["/io/in/B/3/col"] = FakeWing.intReply(5)
        return state
    }

    static func driver(_ wing: FakeWing, rereadEvery: Duration = .zero) -> WingDriver {
        WingDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: wing.port), oscPort: wing.oscPort,
                   timeout: Loopback.replyTimeout, rereadEvery: rereadEvery)
    }

    /// Collects every change the driver sends.
    @MainActor
    final class Changes {
        var all: [SourceChange] = []
        var task: Task<Void, Never>?
    }

    static func collect(_ driver: WingDriver) -> Changes {
        let changes = Changes()
        let stream = driver.sourceChanges()
        changes.task = Task { @MainActor in
            for await change in stream { changes.all.append(change) }
        }
        return changes
    }

    @Test("A rename at the desk reaches its USB Channel at the next re-read")
    func rename() async throws {
        let wing = try await FakeWing(Self.twoChannelWing())
        let driver = Self.driver(wing)
        _ = try await driver.sources(usbChannelCount: 2)
        let changes = Self.collect(driver)

        wing.rename(source: "LCL/1", to: "Kick In")
        try await driver.renewLiveUpdates()

        #expect(await eventually(30) { changes.all == [SourceChange(usbChannel: 1, name: "Kick In")] })
        changes.task?.cancel()
    }

    @Test("A re-patch sends the new Source's name, color and routing")
    func repatch() async throws {
        let wing = try await FakeWing(Self.twoChannelWing())
        let driver = Self.driver(wing)
        _ = try await driver.sources(usbChannelCount: 2)
        let changes = Self.collect(driver)

        wing.repatch(usb: 2, to: "B", 3)
        try await driver.renewLiveUpdates()

        #expect(await eventually(30) {
            changes.all == [SourceChange(usbChannel: 2, name: "Bass DI", color: MixerColor(hue: .green, inverted: false), routedFrom: "B:3")]
        })
        changes.task?.cancel()
    }

    @Test("A recolor reaches its USB Channel")
    func recolor() async throws {
        let wing = try await FakeWing(Self.twoChannelWing())
        let driver = Self.driver(wing)
        _ = try await driver.sources(usbChannelCount: 2)
        let changes = Self.collect(driver)

        wing.recolor(source: "A/5", to: 4)
        try await driver.renewLiveUpdates()

        #expect(await eventually(30) { changes.all == [SourceChange(usbChannel: 2, color: MixerColor(hue: .cyan, inverted: false))] })
        changes.task?.cancel()
    }

    @Test("It never subscribes, so other OSC apps on the desk keep their updates")
    func neverSubscribes() async throws {
        let wing = try await FakeWing(Self.twoChannelWing())
        let driver = Self.driver(wing)
        _ = try await driver.sources(usbChannelCount: 2)
        let changes = Self.collect(driver)
        wing.rename(source: "LCL/1", to: "Kick In")

        for _ in 1...3 { try await driver.renewLiveUpdates() }

        #expect(await eventually(30) { !changes.all.isEmpty })
        #expect(!wing.queries.contains { $0.hasPrefix("/*") || $0.contains("/*") }, "no /*S, /*s or /*b")
        changes.task?.cancel()
    }

    @Test("A re-read isn't started while the last one is still running")
    func skipsWhileInFlight() async throws {
        var state = Self.twoChannelWing()
        state.replyDelay = 0.1   // each read of 2 USB Channels takes about 0.8 s
        let wing = try await FakeWing(state)
        let driver = Self.driver(wing)
        _ = try await driver.sources(usbChannelCount: 2)
        func reads() -> Int { wing.queries.filter { $0 == "/io/out/USB/1/grp" }.count }

        for _ in 1...3 { try await driver.renewLiveUpdates() }

        #expect(await eventually(30) { wing.queries.filter { $0 == "/io/in/A/5/col" }.count == 2 }, "the one re-read finished")
        try await Task.sleep(for: .milliseconds(300))
        #expect(reads() == 2, "the first read, then one re-read; the other two renewals found it running")
    }

    @Test("No re-read before the interval has passed since the last read")
    func waitsForTheInterval() async throws {
        let wing = try await FakeWing(Self.twoChannelWing())
        let driver = Self.driver(wing, rereadEvery: .seconds(3600))
        _ = try await driver.sources(usbChannelCount: 2)

        try await driver.renewLiveUpdates()
        try await Task.sleep(for: .milliseconds(300))

        #expect(wing.queries.filter { $0.hasPrefix("/io/") }.count == 8, "only the first read: 4 queries for each of 2 USB Channels")
    }

    @Test("The interval and the per-read query budget are named: every 5 s, at most 4 queries per USB Channel")
    func constants() async throws {
        #expect(WingDriver.rereadInterval == .seconds(5))
        #expect(WingDriver.queriesPerUSBChannel == 4)
        #expect(WingDriver.queriesPerRead == 192)
        let wing = try await FakeWing(Self.twoChannelWing())
        let driver = Self.driver(wing)
        _ = try await driver.sources(usbChannelCount: 2)
        #expect(wing.queries.filter { $0.hasPrefix("/io/") }.count <= 2 * WingDriver.queriesPerUSBChannel)
    }

    @Test("A WING that stops answering OSC sends no changes and keeps the Link's names")
    func oscGoesQuiet() async throws {
        let wing = try await FakeWing(Self.twoChannelWing())
        let driver = WingDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: wing.port), oscPort: wing.oscPort,
                                timeout: .milliseconds(300), rereadEvery: .zero)
        _ = try await driver.sources(usbChannelCount: 2)
        let changes = Self.collect(driver)
        wing.update { $0.answersOSC = false }

        try await driver.renewLiveUpdates()
        try await Task.sleep(for: .seconds(1))

        #expect(changes.all.isEmpty, "a failed re-read is not a rename to USB 01")
        changes.task?.cancel()
    }
}

/// A rename mid-Take reaches the Link's Sources the way an X32 or XR18 rename does, so the Recorder's existing path
/// (Stem file names, the Reaper project's markers) picks it up.
@MainActor
@Suite("WING live updates through the Link")
struct WingLiveUpdatesLinkTests {
    @Test("A rename at the desk changes the Link's Source")
    func renameReachesTheLink() async throws {
        let wing = try await FakeWing(WingLiveUpdatesTests.twoChannelWing())
        let oscPort = wing.oscPort
        let link = MixerLinkController(timeout: Loopback.replyTimeout, renewEvery: .milliseconds(100)) { endpoint, timeout in
            WingDriver(endpoint: endpoint, oscPort: oscPort, timeout: timeout, rereadEvery: .zero)
        }
        await link.connect(to: "127.0.0.1:\(wing.port)", usbChannelCount: 2)
        #expect(link.sources.first?.name == "Kick")

        wing.rename(source: "LCL/1", to: "Kick In")

        #expect(await eventually(30) { link.sources.first?.name == "Kick In" })
    }
}

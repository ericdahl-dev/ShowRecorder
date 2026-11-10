import MixerLink
import OSC
import Testing

/// The WING family (#417): WING, WING Compact and WING Rack, offered only where `WingAvailability` allows (Debug builds
/// for now). Checked against the WING Remote Protocols document only; no real WING or emulator.
@Suite("WING family")
struct WingFamilyTests {
    static let withWing = MixerFamily.offered(wing: true)

    @Test("A WING's USB audio interface is a WING once WING is offered (names not yet seen on a real WING)",
          arguments: ["WING", "Behringer WING", "WING-RACK", "WING Compact", "wing"])
    func interfaceName(name: String) {
        #expect(MixerFamily(audioInterfaceName: name, offering: Self.withWing) == .wing)
    }

    @Test("Until WING is offered, a WING interface has no family and no WING probe is sent")
    func notOffered() {
        #expect(MixerFamily(audioInterfaceName: "WING", offering: MixerFamily.offered(wing: false)) == nil)
        #expect(!MixerFamily.offered(wing: false).contains(.wing))
        #expect(!MixerFamily.allCases.contains(.wing), "off unless the app turns it on")
        #expect(MixerFamily.probes.map(\.port) == [10024, 10023])
    }

    @Test("Offered, WING comes after the X Air and the X32, so the first family's port stays the default")
    func offeredOrder() {
        #expect(Self.withWing == [.xAir, .x32, .wing])
    }

    @Test("A WING is asked who it is with the plain-text knock WING? on port 2222, which wingemul answers too")
    func probe() {
        #expect(MixerFamily.wing.probe.port == 2222)
        #expect(MixerFamily.wing.probe.request == Array("WING?".utf8))
    }

    @Test("The OSC /? reply (port 2223) carries the same text and reads the same way")
    func oscReply() {
        let reply = OSCMessage("/?", [.string("WING,192.168.1.71,PGM,ngc-full,NO_SERIAL,1.07.2-40-g1b1b292b:develop")]).encoded()
        #expect(MixerFamily.wing.probe.identity(reply)
            == MixerIdentity(networkName: "PGM", model: "ngc-full", firmware: "1.07.2-40-g1b1b292b:develop"))
    }

    @Test("The knock's reply gives the WING's network name, model and firmware, whatever IP it claims (wingemul: 0.0.0.0)")
    func discoveryReply() {
        let reply = Array("WING,0.0.0.0,wingemul,ngc-full,0,3.1.1".utf8)
        #expect(MixerFamily.wing.probe.identity(reply) == MixerIdentity(networkName: "wingemul", model: "ngc-full", firmware: "3.1.1"))
    }

    @Test("Anything else is not a WING", arguments: [
        OSCMessage("/xinfo", [.string("10.0.0.20"), .string("FOH"), .string("X32"), .string("4.06")]).encoded(),
        OSCMessage("/?", [.string("XR18,1,2")]).encoded(),
        Array("WING,1.2.3.4,short".utf8),
        Array("hello".utf8),
    ])
    func notAWing(reply: [UInt8]) {
        #expect(MixerFamily.wing.probe.identity(reply) == nil)
    }

    @Test("A WING's model picks the WING driver", arguments: ["ngc-full", "wing-rack", "wing-compact", "wing-bk", "WING"])
    func readingModel(model: String) {
        #expect(MixerFamily.reading(model: model) == .wing)
    }

    @Test("The WING driver knows a WING sends 48 USB Channels")
    func makesDriver() {
        let driver = MixerFamily.wing.makeDriver(endpoint: MixerEndpoint(host: "10.0.0.30", port: 2222), timeout: .seconds(1))
        #expect(driver.capabilities(for: MixerIdentity(networkName: "", model: "ngc-full", firmware: "")).usbChannelCount == 48)
    }
}

@Suite("WING driver")
struct WingDriverTests {
    @Test("Identifies the WING from its reply to the knock, with no OSC needed (wingemul answers no OSC)")
    func identifies() async throws {
        let wing = try await FakeWing(.init(answersOSC: false))
        let driver = WingDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: wing.port), oscPort: wing.oscPort,
                                timeout: Loopback.replyTimeout)

        #expect(try await driver.identify() == MixerIdentity(networkName: "FOH-WING", model: "ngc-full", firmware: "3.1.1"))
        #expect(wing.queries == ["WING?"])
    }

    @Test("A host that doesn't answer the knock is no WING: no reply, within the timeout")
    func silentHost() async throws {
        let wing = try await FakeWing(.init(identity: "not a wing"))
        let driver = WingDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: wing.oscPort), oscPort: wing.oscPort,
                                timeout: .milliseconds(300))

        await #expect(throws: MixerLinkProblem.noReply(host: "127.0.0.1")) { try await driver.identify() }
    }

    @Test("Until USB routing is read, every USB Channel keeps its USB Channel name")
    func fallbackNames() async throws {
        let wing = try await FakeWing()
        let driver = WingDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: wing.port), oscPort: wing.oscPort,
                                timeout: Loopback.replyTimeout)

        let sources = try await driver.sources(usbChannelCount: 48)

        #expect(sources.map(\.name) == (1...48).map { Source.fallback(usbChannel: $0).name })
    }

    @Test("Detection finds a WING on its port and keeps that connection")
    func detection() async throws {
        let wing = try await FakeWing()
        let detecting = DetectingMixerDriver(host: "127.0.0.1", candidates: [.init(family: .wing, port: wing.port)],
                                             timeout: Loopback.replyTimeout)

        let identity = try await detecting.identify()

        #expect(MixerFamily.reading(model: identity.model) == .wing)
        #expect(wing.queries == ["WING?"])
    }
}

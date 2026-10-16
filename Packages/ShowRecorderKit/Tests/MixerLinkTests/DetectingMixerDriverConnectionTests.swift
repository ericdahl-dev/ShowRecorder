import MixerLink
import Synchronization
import Testing

/// Two connections from one process to the same host and port, alive at once, can collide on macOS (EADDRINUSE,
/// #776), so the Link keeps the connection that identified the Mixer instead of opening a second one.
@Suite("Detecting the Mixer: one connection per Link (#776)")
struct DetectingMixerDriverConnectionTests {
    /// Builds `FakeMixerDriver`s that answer as `model`, and remembers each one made.
    private final class Factory: Sendable {
        private let log = Mutex<[(family: MixerFamily, port: UInt16, driver: FakeMixerDriver)]>([])
        let model: String
        let answersOnlyAsFamily: MixerFamily?
        init(model: String, answersOnlyAsFamily: MixerFamily? = nil) {
            self.model = model
            self.answersOnlyAsFamily = answersOnlyAsFamily
        }

        func make(_ family: MixerFamily, _ endpoint: MixerEndpoint, _: Duration) -> any MixerDriver {
            var state = FakeMixerDriver.State()
            state.identity = MixerIdentity(networkName: "FOH", model: model, firmware: "1.22")
            // An XR18 doesn't answer on the X32's port, so the X32 probe never wins the race.
            if let only = answersOnlyAsFamily, family != only { state.problem = .noReply(host: endpoint.host) }
            let driver = FakeMixerDriver(state)
            log.withLock { $0.append((family, endpoint.port, driver)) }
            return driver
        }

        var made: [(family: MixerFamily, port: UInt16, driver: FakeMixerDriver)] { log.withLock { $0 } }
    }

    private func detecting(_ candidates: [DetectingMixerDriver.Candidate], _ factory: Factory) -> DetectingMixerDriver {
        DetectingMixerDriver(host: "10.0.0.20", candidates: candidates, timeout: .seconds(1)) { family, endpoint, timeout in
            factory.make(family, endpoint, timeout)
        }
    }

    @Test("An address with one port builds one driver, and the Link keeps it")
    func oneCandidateOneDriver() async throws {
        let factory = Factory(model: "XR18")
        let driver = detecting([.init(family: .xAir, port: 10024)], factory)

        _ = try await driver.identify()
        _ = try await driver.sources(usbChannelCount: 18)
        _ = try await driver.identify()  // the Link asking again, on the same connection

        #expect(factory.made.count == 1)
        #expect(factory.made.first?.driver.state.withLock { $0.sourceReads } == [18], "the Sources were read on the driver that identified")
    }

    @Test("Asking both families builds one driver each, and the one that answered is kept")
    func twoCandidatesNoExtraDriver() async throws {
        let factory = Factory(model: "XR18", answersOnlyAsFamily: .xAir)
        let driver = detecting([.init(family: .xAir, port: 10024), .init(family: .x32, port: 10023)], factory)

        _ = try await driver.identify()
        _ = try await driver.sources(usbChannelCount: 18)

        #expect(factory.made.count == 2)
        let reads = factory.made.map { ($0.family, $0.driver.state.withLock { $0.sourceReads }) }
        #expect(reads.first { $0.0 == .xAir }?.1 == [18], "the Sources were read on the probe that answered")
        #expect(reads.first { $0.0 == .x32 }?.1 == [], "and not on the one that didn't")
    }

    @Test("A Mixer that names another family than the one asked gets that family's driver")
    func otherFamilyBuildsItsOwn() async throws {
        let factory = Factory(model: "X32")
        let driver = detecting([.init(family: .xAir, port: 10024)], factory)

        let identity = try await driver.identify()

        #expect(identity.model == "X32")
        #expect(factory.made.count == 2)
        #expect(factory.made.last?.family == .x32)
    }
}

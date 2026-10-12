import MixerLink
import Testing

/// The Mixer Link finds out which Mixer answers, X-Air or X32, and talks to it with that one's driver (#199).
@Suite("Detecting the Mixer")
struct DetectingMixerDriverTests {
    @Test("An X32 answering on its own port is read as an X32: 32 USB Channels, its channel names")
    func findsAnX32() async throws {
        var silent = FakeXAirMixer.State()
        silent.answers = false
        let xAirPort = try await FakeXAirMixer(silent)
        var state = FakeXAirMixer.State.x32()
        state.channels[31] = .init(name: "Audience R", color: 6)
        let x32 = try await FakeXAirMixer(state)
        let driver = DetectingMixerDriver(host: "127.0.0.1", ports: [xAirPort.port, x32.port], timeout: .seconds(1))

        let identity = try await driver.identify()
        let sources = try await driver.sources(usbChannelCount: 32)

        #expect(identity.model == "X32")
        #expect(driver.capabilities(for: identity).usbChannelCount == 32)
        #expect(sources[safe: 31]?.name == "Audience R")
    }

    @Test("An XR18 is read as an X-Air: 18 USB Channels")
    func findsAnXR18() async throws {
        let xr18 = try await FakeXAirMixer()
        var silent = FakeXAirMixer.State.x32()
        silent.answers = false
        let x32Port = try await FakeXAirMixer(silent)
        let driver = DetectingMixerDriver(host: "127.0.0.1", ports: [xr18.port, x32Port.port], timeout: .seconds(1))

        let identity = try await driver.identify()

        #expect(identity.model == "XR18")
        #expect(driver.capabilities(for: identity).usbChannelCount == 18)
    }

    @Test("Every model in the X32 and M32 families gets the X32 driver", arguments: ["X32", "X32RACK", "X32C", "X32P", "M32", "M32R", "M32C"])
    func x32Family(model: String) async throws {
        let mixer = try await FakeXAirMixer(.x32(model: model))
        let driver = DetectingMixerDriver(host: "127.0.0.1", ports: [mixer.port], timeout: .seconds(1))

        let identity = try await driver.identify()

        #expect(driver.capabilities(for: identity).usbChannelCount == 32)
    }

    @Test("When nothing answers on any port, the Link says no Mixer answered at that address")
    func nothingAnswers() async throws {
        var silent = FakeXAirMixer.State()
        silent.answers = false
        let mixer = try await FakeXAirMixer(silent)
        let driver = DetectingMixerDriver(host: "127.0.0.1", ports: [mixer.port], timeout: .milliseconds(300))

        await #expect(throws: MixerLinkProblem.noReply(host: "127.0.0.1")) { try await driver.identify() }
    }

    @Test("The X-Air's 10024 and the X32's 10023 are both asked, the given one first; any other port is asked alone")
    func candidatePorts() {
        #expect(DetectingMixerDriver.ports(for: MixerEndpoint(host: "10.0.0.20", port: 10024)) == [10024, 10023])
        #expect(DetectingMixerDriver.ports(for: MixerEndpoint(host: "10.0.0.20", port: 10023)) == [10023, 10024])
        #expect(DetectingMixerDriver.ports(for: MixerEndpoint(host: "10.0.0.20", port: 9000)) == [9000])
    }
}

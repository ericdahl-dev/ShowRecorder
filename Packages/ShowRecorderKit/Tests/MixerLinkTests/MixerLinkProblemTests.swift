import Network
@testable import MixerLink
import Testing

@Suite("Mixer Link problems")
struct MixerLinkProblemTests {
    @Test("A Mixer that never answers is reported as no reply")
    func silentMixerIsNoReply() async throws {
        var state = FakeXAirMixer.State()
        state.answers = false
        let mixer = try await FakeXAirMixer(state)
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port), timeout: .milliseconds(200))

        await #expect(throws: MixerLinkProblem.noReply(host: "127.0.0.1")) {
            try await driver.identify()
        }
    }

    @Test("An address with nothing listening is reported as no reply")
    func nothingListeningIsNoReply() async throws {
        // Grab a free loopback port, then close it so nothing listens there.
        let port = try await FakeXAirMixer().port
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: port), timeout: .milliseconds(300))

        await #expect(throws: MixerLinkProblem.noReply(host: "127.0.0.1")) {
            try await driver.identify()
        }
    }

    @Test("Network errors map to problems an operator can act on", arguments: [
        (NWError.posix(.ENETUNREACH), MixerLinkProblem.networkUnreachable),
        (NWError.posix(.EHOSTUNREACH), MixerLinkProblem.networkUnreachable),
        (NWError.posix(.ECONNREFUSED), MixerLinkProblem.noReply(host: "10.0.0.9")),
        (NWError.dns(-65570), MixerLinkProblem.localNetworkDenied),
        (NWError.posix(.ETIMEDOUT), MixerLinkProblem.noReply(host: "10.0.0.9")),
        (NWError.posix(.ECONNRESET), MixerLinkProblem.noReply(host: "10.0.0.9")),
        (NWError.posix(.EADDRNOTAVAIL), MixerLinkProblem.networkUnreachable),  // Wi-Fi changed or dropped
        (NWError.dns(-65554), MixerLinkProblem.hostNotFound("10.0.0.9")),  // no such record
        (NWError.dns(-65538), MixerLinkProblem.hostNotFound("10.0.0.9")),  // no such name
        (NWError.dns(-65568), MixerLinkProblem.hostNotFound("10.0.0.9")),  // timed out
        (NWError.posix(.EINVAL), MixerLinkProblem.cantConnect(host: "10.0.0.9", port: 10024, code: 22)),
    ])
    func networkErrorsMap(error: NWError, expected: MixerLinkProblem) {
        #expect(MixerLinkProblem(error, path: nil, host: "10.0.0.9", port: 10024) == expected)
    }

    @Test("A Network error with no words of its own says where it couldn't connect and what to try, not \"NWError error 22\"")
    func unmappedIsReadable() {
        let message = MixerLinkProblem(.posix(.EINVAL), path: nil, host: "192.168.1.146", port: 10024).message
        #expect(message.contains("192.168.1.146:10024"))
        #expect(message.contains("(error 22)"))
        #expect(!message.contains("NWError"))
        #expect(!message.contains("couldn’t be completed"))
    }

    @Test("Every problem has a message that says what to do")
    func everyProblemHasMessage() {
        let problems: [MixerLinkProblem] = [
            .noReply(host: "10.0.0.9"), .networkUnreachable, .localNetworkDenied, .invalidAddress("10.0.0"), .hostNotFound("xr18.local"),
            .cantConnect(host: "10.0.0.9", port: 10024, code: 22), .other("x"),
        ]
        for problem in problems {
            #expect(!problem.message.isEmpty)
        }
        #expect(MixerLinkProblem.noReply(host: "10.0.0.9").message.contains("10.0.0.9"))
        #expect(MixerLinkProblem.localNetworkDenied.message.contains("Local Network"))
    }

    @Test("A bad address is called an address, not an IP address: a name such as xr18.local is fine too")
    func invalidAddressWording() {
        #expect(MixerLinkProblem.invalidAddress("xr18..local").message == "\"xr18..local\" isn't a valid Mixer address. Enter its IP address, such as 192.168.1.20, or its name, such as xr18.local.")
    }
}

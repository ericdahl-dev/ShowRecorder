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
    ])
    func networkErrorsMap(error: NWError, expected: MixerLinkProblem) {
        #expect(MixerLinkProblem(error, path: nil, host: "10.0.0.9") == expected)
    }

    @Test("Every problem has a message that says what to do")
    func everyProblemHasMessage() {
        let problems: [MixerLinkProblem] = [
            .noReply(host: "10.0.0.9"), .networkUnreachable, .localNetworkDenied, .invalidAddress("10.0.0"), .other("x"),
        ]
        for problem in problems {
            #expect(!problem.message.isEmpty)
        }
        #expect(MixerLinkProblem.noReply(host: "10.0.0.9").message.contains("10.0.0.9"))
        #expect(MixerLinkProblem.localNetworkDenied.message.contains("Local Network"))
    }
}

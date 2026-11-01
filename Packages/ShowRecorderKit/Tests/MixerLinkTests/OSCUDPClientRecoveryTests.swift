import Foundation
@testable import MixerLink
import Network
import OSC
import Testing

/// The UDP client rebuilds its connection after it fails, so the Link can come back by itself (#321).
@Suite("OSC client recovery")
struct OSCUDPClientRecoveryTests {
    func client(for mixer: FakeXAirMixer) throws -> OSCUDPClient {
        OSCUDPClient(endpoint: try #require(MixerEndpoint(parsing: "127.0.0.1:\(mixer.port)")))
    }

    @Test("After the connection fails, the next request opens a new one and gets its reply")
    func rebuildsAfterFailure() async throws {
        let mixer = try await FakeXAirMixer()
        let client = try client(for: mixer)
        _ = try await client.request(OSCMessage("/xinfo", []), timeout: Loopback.replyTimeout)

        await client.connectionFailed(.posix(.ECONNREFUSED))

        let reply = try await client.request(OSCMessage("/xinfo", []), timeout: Loopback.replyTimeout)
        #expect(reply.address == "/xinfo")
    }

    @Test("After a receive error, replies still arrive: receiving starts again on a new connection")
    func receivesAfterReceiveError() async throws {
        let mixer = try await FakeXAirMixer()
        let client = try client(for: mixer)
        _ = try await client.request(OSCMessage("/xinfo", []), timeout: Loopback.replyTimeout)

        await client.receiveFailed()

        let reply = try await client.request(OSCMessage("/xinfo", []), timeout: Loopback.replyTimeout)
        #expect(reply.address == "/xinfo")
    }

    @Test("A receive error fails the requests waiting on that connection at once, not at their timeout (#890)")
    func receiveErrorFailsPending() async throws {
        var silent = FakeXAirMixer.State()
        silent.answers = false
        let mixer = try await FakeXAirMixer(silent)
        let client = try client(for: mixer)
        // The request may not be pending yet when the first error comes, so the error repeats until the request ends.
        let errors = Task {
            while !Task.isCancelled {
                await client.receiveFailed()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { errors.cancel() }

        let started = ContinuousClock.now
        _ = try? await client.request(OSCMessage("/xinfo", []), timeout: .seconds(30))

        #expect(ContinuousClock.now - started < Loopback.replyTimeout, "the request failed on the receive error")
    }
}

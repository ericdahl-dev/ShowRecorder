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
        _ = try await client.request(OSCMessage("/xinfo", []), timeout: .seconds(2))

        await client.connectionFailed(.posix(.ECONNREFUSED))

        let reply = try await client.request(OSCMessage("/xinfo", []), timeout: .seconds(2))
        #expect(reply.address == "/xinfo")
    }

    @Test("After a receive error, replies still arrive: receiving starts again on a new connection")
    func receivesAfterReceiveError() async throws {
        let mixer = try await FakeXAirMixer()
        let client = try client(for: mixer)
        _ = try await client.request(OSCMessage("/xinfo", []), timeout: .seconds(2))

        await client.receiveFailed()

        let reply = try await client.request(OSCMessage("/xinfo", []), timeout: .seconds(2))
        #expect(reply.address == "/xinfo")
    }
}

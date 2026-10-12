@testable import MixerLink
import OSC
import Testing

/// Pushed changes reach the Link in the order the Mixer sent them, so two quick renames never end on the older name.
@Suite("OSC client order")
struct OSCUDPClientOrderTests {
    @Test("300 renames pushed back to back arrive in the order they were sent")
    func pushesKeepTheirOrder() async throws {
        let mixer = try await FakeXAirMixer()
        let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1", port: mixer.port))
        var changes = driver.sourceChanges().makeAsyncIterator()
        try await driver.renewLiveUpdates()

        for n in 1...300 { mixer.rename(channel: 1, to: "Take \(n)") }

        var names: [String] = []
        while names.count < 300, let change = await changes.next() { names.append(change.name ?? "") }
        #expect(names == (1...300).map { "Take \($0)" })
    }
}

import Foundation
@testable import MixerLink
import Testing

/// Find mixers: ask every address on the device's own network for /xinfo (#289).
@Suite("Mixer scan")
struct MixerScanTests {
    @Test("On a home network (a /24) every other address is asked: not the network, the broadcast or the device itself")
    func homeNetwork() throws {
        let hosts = try #require(ScanRange(address: "192.168.1.23", netmask: "255.255.255.0")).hosts
        #expect(hosts.count == 253)
        #expect(hosts.first == "192.168.1.1")
        #expect(hosts.last == "192.168.1.254")
        #expect(!hosts.contains("192.168.1.23"))
        #expect(!hosts.contains("192.168.1.0"))
        #expect(!hosts.contains("192.168.1.255"))
    }

    @Test("A big network (a /16) is scanned only in the /22 around the device: at most 1,022 addresses")
    func bigNetwork() throws {
        let hosts = try #require(ScanRange(address: "10.20.5.7", netmask: "255.255.0.0")).hosts
        #expect(hosts.count == 1_021)
        #expect(hosts.first == "10.20.4.1")
        #expect(hosts.last == "10.20.7.254")
    }

    @Test("The scan finds a mixer that answers /xinfo, with its name, model and address, and only asks /xinfo")
    func findsMixer() async throws {
        let mixer = try await FakeXAirMixer()
        let found = await MixerScanner.scan(hosts: ["127.0.0.1"], port: mixer.port, timeout: .seconds(1))
        #expect(found == [FoundMixer(host: "127.0.0.1", identity: MixerIdentity(networkName: "FOH-XR18", model: "XR18", firmware: "1.22"))])
        #expect(mixer.queries == ["/xinfo"])
    }

    @Test("A mixer that doesn't answer isn't listed, and the scan still ends at its timeout")
    func silent() async throws {
        var state = FakeXAirMixer.State()
        state.answers = false
        let mixer = try await FakeXAirMixer(state)
        let started = ContinuousClock.now
        let found = await MixerScanner.scan(hosts: ["127.0.0.1"], port: mixer.port, timeout: .milliseconds(300))
        #expect(found.isEmpty)
        #expect(ContinuousClock.now - started < .seconds(2))
    }
}

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
        let found = await MixerScanner.scan(hosts: ["127.0.0.1"], ports: [mixer.port], timeout: Loopback.mixedTimeout)
        #expect(found == [FoundMixer(host: "127.0.0.1", identity: MixerIdentity(networkName: "FOH-XR18", model: "XR18", firmware: "1.22"))])
        #expect(mixer.queries == ["/xinfo"])
    }

    @Test("A mixer that doesn't answer isn't listed, and the scan still ends at its timeout")
    func silent() async throws {
        var state = FakeXAirMixer.State()
        state.answers = false
        let mixer = try await FakeXAirMixer(state)
        let started = ContinuousClock.now
        let found = await MixerScanner.scan(hosts: ["127.0.0.1"], ports: [mixer.port], timeout: .milliseconds(300))
        #expect(found.isEmpty)
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test("An X32 answering on its own port (10023, not the X-Air's 10024) is found too, from the same scan")
    func findsAnX32OnItsPort() async throws {
        var silent = FakeXAirMixer.State()
        silent.answers = false
        let xAirPort = try await FakeXAirMixer(silent)
        let x32 = try await FakeXAirMixer(.x32())
        let found = await MixerScanner.scan(hosts: ["127.0.0.1"], ports: [xAirPort.port, x32.port], timeout: Loopback.mixedTimeout)
        #expect(found == [FoundMixer(host: "127.0.0.1", identity: MixerIdentity(networkName: "FOH-X32", model: "X32", firmware: "4.06"))])
    }

    @Test("Find Mixers asks the X-Air's port and the X32's by default")
    func defaultPorts() {
        #expect(MixerScanner.defaultPorts == [10024, 10023])
    }

    @Test("Find mixers asks each family its own way: a family probed with plain text, not /xinfo, is found too (#442)")
    func findsAFamilyWithItsOwnProbe() async throws {
        let mixer = try await FakeTextMixer(answering: "WHO?", with: "FOH,TEST,1.0")
        let probe = MixerProbe(port: mixer.port, request: Array("WHO?".utf8)) { data in
            let parts = String(decoding: data, as: UTF8.self).split(separator: ",").map(String.init)
            return parts.count == 3 ? MixerIdentity(networkName: parts[0], model: parts[1], firmware: parts[2]) : nil
        }
        let found = await MixerScanner.scan(hosts: ["127.0.0.1"], probes: [probe], timeout: Loopback.mixedTimeout)
        #expect(found == [FoundMixer(host: "127.0.0.1", identity: MixerIdentity(networkName: "FOH", model: "TEST", firmware: "1.0"))])
        #expect(mixer.requests == ["WHO?"])
    }

    @Test("By default Find mixers asks every family in the registry")
    func defaultProbes() {
        #expect(MixerScanner.defaultPorts == MixerFamily.probes.map(\.port))
    }
}

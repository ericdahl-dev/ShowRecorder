import MixerLink
import OSC
import Testing

/// Which mixer family an audio interface belongs to, from its name, so Mixer Link is offered only for mixers it can
/// talk to (#365) and a mixer pack can be matched to it (#412).
@Suite("Mixer family")
struct MixerFamilyTests {
    @Test("An X Air over USB is an X Air (\"X18/XR18\" as the XR18 shows on the Mac)",
          arguments: ["X18/XR18", "XR18", "MR18", "X18/XR18 #2"])
    func xAir(name: String) {
        #expect(MixerFamily(audioInterfaceName: name) == .xAir)
    }

    @Test("An X32 or M32 USB card is an X32 (names not yet seen on a real card)",
          arguments: ["X-USB", "X32", "X32 Rack", "M32", "DN32-USB"])
    func x32(name: String) {
        #expect(MixerFamily(audioInterfaceName: name) == .x32)
    }

    @Test("Anything else has no family: Mixer Link isn't offered",
          arguments: ["iPhone Microphone", "MacBook Pro Microphone", "Demo signal (18 channels)", "Audient EVO4",
                      "DJM-A9", "Scarlett 18i20 USB", ""])
    func none(name: String) {
        #expect(MixerFamily(audioInterfaceName: name) == nil)
    }

    @Test("Each family's Mixers listen on their own port: the X Air on 10024, the X32 on 10023 (#442)")
    func ports() {
        #expect(MixerFamily.xAir.probe.port == 10024)
        #expect(MixerFamily.x32.probe.port == 10023)
        #expect(MixerFamily.probes.map(\.port) == [10024, 10023])
    }

    @Test("A model from /xinfo picks the family whose driver reads it; an unknown one is read as an X Air, as before",
          arguments: [("X32", MixerFamily.x32), ("X32RACK", .x32), ("m32r", .x32), ("XR18", .xAir), ("MR18", .xAir),
                      ("XR12", .xAir), ("FOO", .xAir)])
    func readingModel(model: String, family: MixerFamily) {
        #expect(MixerFamily.reading(model: model) == family)
    }

    @Test("A family makes its own driver: an X32 driver reads all 32 USB Channels, an X Air one 18 on an XR18")
    func makesDriver() {
        let endpoint = MixerEndpoint(host: "10.0.0.20")
        let x32 = MixerFamily.x32.makeDriver(endpoint: endpoint, timeout: .seconds(1))
        let xAir = MixerFamily.xAir.makeDriver(endpoint: endpoint, timeout: .seconds(1))
        #expect(x32.capabilities(for: MixerIdentity(networkName: "", model: "X32", firmware: "")).usbChannelCount == 32)
        #expect(xAir.capabilities(for: MixerIdentity(networkName: "", model: "XR18", firmware: "")).usbChannelCount == 18)
    }

    @Test("The /xinfo probe reads a reply's network name, model and firmware, and ignores anything else")
    func xinfoProbe() {
        let probe = MixerFamily.x32.probe
        let reply = OSCMessage("/xinfo", [.string("10.0.0.20"), .string("FOH"), .string("X32"), .string("4.06")]).encoded()
        #expect(probe.request == OSCMessage("/xinfo").encoded())
        #expect(probe.identity(reply) == MixerIdentity(networkName: "FOH", model: "X32", firmware: "4.06"))
        #expect(probe.identity(OSCMessage("/status").encoded()) == nil)
    }

    @Test("An address typed without a port is asked on the first family's port first, from the registry")
    func defaultPort() {
        #expect(MixerEndpoint.defaultPort == MixerFamily.probes.first?.port)
        #expect(MixerEndpoint(host: "10.0.0.5").port == MixerEndpoint.defaultPort)
        #expect(MixerEndpoint(parsing: "10.0.0.5")?.port == MixerEndpoint.defaultPort)
    }

    @Test("Every family's driver offers its preamp control, so Mix Hold and auto-gain reach it (#442)",
          arguments: MixerFamily.allCases)
    func gainControl(family: MixerFamily) {
        let driver = family.makeDriver(endpoint: MixerEndpoint(host: "10.0.0.20"), timeout: .seconds(1))
        #expect(driver.gainControl != nil)
    }
}

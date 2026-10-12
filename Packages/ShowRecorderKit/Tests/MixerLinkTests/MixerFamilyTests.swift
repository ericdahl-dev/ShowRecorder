import MixerLink
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
}

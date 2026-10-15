import MixerLink
import Testing

@Suite("Mixer Link path")
struct MixerLinkPathTests {
    @Test("The path reads as the operator knows it")
    func name() {
        #expect(MixerLinkPath.wifi.name == "Wi-Fi")
    }
}

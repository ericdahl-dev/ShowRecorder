import MixerLink
import Testing

@Suite("Mixer capabilities")
struct MixerCapabilitiesTests {
    let driver = XAirDriver(endpoint: MixerEndpoint(host: "127.0.0.1"))

    @Test("The XR18 and MR18 send 18 USB Channels and the X-Air driver can name all 18", arguments: ["XR18", "MR18"])
    func eighteenChannelXAir(model: String) {
        let capabilities = driver.capabilities(for: MixerIdentity(networkName: "FOH", model: model, firmware: "1.22"))

        #expect(capabilities == MixerCapabilities(usbChannelCount: 18, nameableUSBChannelCount: 18))
    }

    @Test("The XR12 and XR16 send no multichannel USB audio", arguments: ["XR12", "XR16"])
    func xAirWithoutMultichannelUSB(model: String) {
        let capabilities = driver.capabilities(for: MixerIdentity(networkName: "FOH", model: model, firmware: "1.22"))

        #expect(capabilities.usbChannelCount == nil)
    }

    @Test("An X-Air model the driver doesn't know has no known USB Channel count")
    func unknownModel() {
        let capabilities = driver.capabilities(for: MixerIdentity(networkName: "FOH", model: "XR99", firmware: "1.22"))

        #expect(capabilities.usbChannelCount == nil)
    }
}

import MixerLink
import Recording
import Testing

@Suite("USB Channel shortfall warning")
struct USBChannelShortfallTests {
    let xr18 = MixerIdentity(networkName: "FOH-XR18", model: "XR18", firmware: "1.22")
    let xr18Capabilities = MixerCapabilities(usbChannelCount: 18, nameableUSBChannelCount: 18)
    let xr16 = MixerIdentity(networkName: "Stage", model: "XR16", firmware: "1.22")
    let xr16Capabilities = MixerCapabilities(usbChannelCount: nil, nameableUSBChannelCount: 0)

    @Test("With no Mixer identified, any channel count is just shown", arguments: [1, 2, 8, 16, 18, 32])
    func noMixerNoWarning(count: Int) {
        #expect(USBChannelShortfall.check(usbChannelCount: count, offeredChannelCount: nil, mixer: nil, capabilities: nil) == nil)
    }

    @Test("A device sending fewer USB Channels than the identified Mixer sends is a shortfall that names the Mixer", arguments: [8, 16])
    func fewerThanIdentifiedMixer(count: Int) throws {
        let shortfall = try #require(USBChannelShortfall.check(
            usbChannelCount: count, offeredChannelCount: nil, mixer: xr18, capabilities: xr18Capabilities))

        #expect(shortfall.message == "This device sends \(count) USB Channels. The XR18 (FOH-XR18) sends 18, so some of the Mixer won't be recorded.")
    }

    @Test("A device sending at least what the identified Mixer sends is fine", arguments: [18, 32])
    func enoughForIdentifiedMixer(count: Int) {
        #expect(USBChannelShortfall.check(usbChannelCount: count, offeredChannelCount: nil, mixer: xr18, capabilities: xr18Capabilities) == nil)
    }

    @Test("An identified Mixer with no multichannel USB raises no warning", arguments: [2, 8, 16, 18, 32])
    func mixerWithoutUSBCountNoWarning(count: Int) {
        #expect(USBChannelShortfall.check(usbChannelCount: count, offeredChannelCount: nil, mixer: xr16, capabilities: xr16Capabilities) == nil)
    }

    @Test("The system granting fewer channels than the input offers is a shortfall, without naming a Mixer")
    func systemGrantedFewer() throws {
        let shortfall = try #require(USBChannelShortfall.check(
            usbChannelCount: 8, offeredChannelCount: 32, mixer: nil, capabilities: nil))

        #expect(shortfall.message == "This input offers 32 channels, but the system is sending the recorder 8 USB Channels, so some channels won't be recorded.")
        #expect(!shortfall.message.contains("XR18"))
    }

    @Test("The system granting every offered channel is fine", arguments: [8, 16, 18, 32])
    func systemGrantedAll(count: Int) {
        #expect(USBChannelShortfall.check(usbChannelCount: count, offeredChannelCount: count, mixer: nil, capabilities: nil) == nil)
    }

    @Test("Nothing Armed means nothing to warn about")
    func nothingArmed() {
        #expect(USBChannelShortfall.check(usbChannelCount: 0, offeredChannelCount: nil, mixer: xr18, capabilities: xr18Capabilities) == nil)
    }

    @Test("One USB Channel reads in the singular")
    func singular() throws {
        let shortfall = try #require(USBChannelShortfall.check(
            usbChannelCount: 1, offeredChannelCount: nil, mixer: xr18, capabilities: xr18Capabilities))

        #expect(shortfall.message.hasPrefix("This device sends 1 USB Channel."))
    }
}

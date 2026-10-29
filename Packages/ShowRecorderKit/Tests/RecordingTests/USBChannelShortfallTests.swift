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

    @Test("A device sending fewer USB Channels than the identified Mixer sends is a shortfall that names the Mixer, short enough for 2 lines on an iPhone (#292)", arguments: [3, 8, 16])
    func fewerThanIdentifiedMixer(count: Int) throws {
        let shortfall = try #require(USBChannelShortfall.check(
            usbChannelCount: count, offeredChannelCount: nil, mixer: xr18, capabilities: xr18Capabilities))

        #expect(shortfall.message == "Only \(count) of the XR18's 18 USB Channels are coming in. Get the XR18 ready to record all 18.")
        #expect(shortfall.message.count <= 90)
    }

    @Test("A 1- or 2-channel input (the iPhone's microphone, a stereo interface) with the Mixer linked over Wi-Fi is on purpose: no warning", arguments: [1, 2])
    func micWithLinkedMixer(count: Int) {
        #expect(USBChannelShortfall.check(usbChannelCount: count, offeredChannelCount: nil, mixer: xr18, capabilities: xr18Capabilities) == nil)
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

    @Test("Nothing Ready means nothing to warn about")
    func nothingReady() {
        #expect(USBChannelShortfall.check(usbChannelCount: 0, offeredChannelCount: nil, mixer: xr18, capabilities: xr18Capabilities) == nil)
    }
}

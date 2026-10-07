import Recording
import Testing

@Suite("Input device preference")
struct InputDevicePreferenceTests {
    let mic = InputDeviceInfo(id: "mic", name: "MacBook Pro Microphone", inputChannelCount: 1, sampleRate: 48_000)
    let stereo = InputDeviceInfo(id: "usb2", name: "USB Interface", inputChannelCount: 2, sampleRate: 48_000)

    func device(_ channels: Int) -> InputDeviceInfo {
        InputDeviceInfo(id: "in\(channels)", name: "\(channels)-in", inputChannelCount: channels, sampleRate: 48_000)
    }

    @Test("More than 2 inputs is multichannel", arguments: [(1, false), (2, false), (3, true), (8, true), (16, true), (18, true), (32, true)])
    func multichannel(channels: Int, expected: Bool) {
        #expect(device(channels).isMultichannel == expected)
    }

    @Test("A multichannel device of any size comes before the built-in mic, even when the mic is the system default", arguments: [8, 16, 18, 32])
    func multichannelBeforeMic(channels: Int) {
        let ordered = InputDeviceInfo.preferredOrder([mic, stereo, device(channels)], defaultID: "mic")

        #expect(ordered.map(\.id) == ["in\(channels)", "mic", "usb2"])
    }

    @Test("Several multichannel devices are ordered most channels first")
    func mostChannelsFirst() {
        let ordered = InputDeviceInfo.preferredOrder([device(8), mic, device(32), device(18), device(16)], defaultID: nil)

        #expect(ordered.map(\.inputChannelCount) == [32, 18, 16, 8, 1])
    }

    @Test("Without a multichannel device the system default comes first, the rest keep their order")
    func defaultFirstOtherwise() {
        let other = InputDeviceInfo(id: "other", name: "Other mic", inputChannelCount: 1, sampleRate: 48_000)
        let ordered = InputDeviceInfo.preferredOrder([mic, other, stereo], defaultID: "usb2")

        #expect(ordered.map(\.id) == ["usb2", "mic", "other"])
    }
}

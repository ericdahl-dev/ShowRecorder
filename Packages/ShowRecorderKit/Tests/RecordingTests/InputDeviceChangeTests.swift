import Recording
import Testing

@Suite("Input device list changes")
struct InputDeviceChangeTests {
    let mic = InputDeviceInfo(id: "mic", name: "MacBook Pro Microphone", inputChannelCount: 1, sampleRate: 48_000)
    let xr18 = InputDeviceInfo(id: "xr18", name: "XR18", inputChannelCount: 18, sampleRate: 48_000)
    let interface = InputDeviceInfo(id: "usb2", name: "USB Interface", inputChannelCount: 2, sampleRate: 48_000)

    @Test("The Armed selection is kept when another device appears")
    func keepsSelectionWhenAnotherDeviceAppears() {
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18, mic, interface],
            selectedID: "xr18", armed: xr18, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .none, stopsTake: false, message: nil))
    }

    @Test("Unplugging the Armed device disarms and says so")
    func unpluggingArmedDeviceDisarms() {
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [mic],
            selectedID: "xr18", armed: xr18, isRecording: false)

        #expect(change.selectedID == nil)
        #expect(change.action == .disarm)
        #expect(!change.stopsTake)
        #expect(change.message == "XR18 was disconnected, so the recorder is no longer Armed. Reconnect it or choose another input.")
    }

    @Test("Unplugging the Armed device during a Take stops the Take and says so")
    func unpluggingDuringTakeStopsIt() {
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [mic],
            selectedID: "xr18", armed: xr18, isRecording: true)

        #expect(change.selectedID == nil)
        #expect(change.action == .disarm)
        #expect(change.stopsTake)
        #expect(change.message == "XR18 was disconnected during the Take. Recording stopped and the Stems recorded so far were saved.")
    }

    @Test("A multichannel device that appears while nothing is Armed is selected and Armed")
    func fullDeviceAppearingWhileNothingArmedIsArmed() {
        let change = InputDeviceChange.decide(
            old: [mic], new: [xr18, mic],
            selectedID: nil, armed: nil, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .arm, stopsTake: false, message: nil))
    }

    @Test("A multichannel device that appears while a built-in mic is Armed takes over")
    func fullDeviceReplacesSmallArmedDevice() {
        let change = InputDeviceChange.decide(
            old: [mic], new: [xr18, mic],
            selectedID: "mic", armed: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .arm, stopsTake: false, message: nil))
    }

    @Test("A multichannel device of any size takes over from a built-in mic", arguments: [8, 16, 18, 32])
    func anyMultichannelDeviceTakesOver(channels: Int) {
        let device = InputDeviceInfo(id: "multi", name: "Interface", inputChannelCount: channels, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [mic], new: [device, mic],
            selectedID: "mic", armed: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "multi", action: .arm, stopsTake: false, message: nil))
    }

    @Test("A stereo interface that appears doesn't take over from a built-in mic")
    func stereoDoesNotTakeOver() {
        let change = InputDeviceChange.decide(
            old: [mic], new: [mic, interface],
            selectedID: "mic", armed: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "mic", action: .none, stopsTake: false, message: nil))
    }

    @Test("A bigger device that appears doesn't move an Armed multichannel device")
    func biggerDeviceDoesNotReplaceMultichannel() {
        let x32 = InputDeviceInfo(id: "x32", name: "X-USB", inputChannelCount: 32, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [x32, xr18, mic],
            selectedID: "xr18", armed: xr18, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .none, stopsTake: false, message: nil))
    }

    @Test("When several multichannel devices appear at once, the one with the most channels is Armed")
    func mostChannelsWinsAmongArrivals() {
        let eight = InputDeviceInfo(id: "eight", name: "8-in", inputChannelCount: 8, sampleRate: 48_000)
        let x32 = InputDeviceInfo(id: "x32", name: "X-USB", inputChannelCount: 32, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [mic], new: [eight, mic, x32],
            selectedID: "mic", armed: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "x32", action: .arm, stopsTake: false, message: nil))
    }

    @Test("A running Take is never moved to a device that appears")
    func takeIsNotMovedToNewDevice() {
        let change = InputDeviceChange.decide(
            old: [mic], new: [xr18, mic],
            selectedID: "mic", armed: mic, isRecording: true)

        #expect(change == InputDeviceChange(selectedID: "mic", action: .none, stopsTake: false, message: nil))
    }

    @Test("A smaller device the operator chose is kept when the multichannel device was already there")
    func operatorChoiceKeptWhenFullDeviceWasPresent() {
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18, mic, interface],
            selectedID: "mic", armed: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "mic", action: .none, stopsTake: false, message: nil))
    }

    @Test("If the Armed device goes and a multichannel device arrives at once, the new one is Armed and the loss is still reported")
    func swapInOneChange() {
        let mr18 = InputDeviceInfo(id: "mr18", name: "MR18", inputChannelCount: 18, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [mr18, mic],
            selectedID: "xr18", armed: xr18, isRecording: true)

        #expect(change.selectedID == "mr18")
        #expect(change.action == .arm)
        #expect(change.stopsTake)
        #expect(change.message == "XR18 was disconnected during the Take. Recording stopped and the Stems recorded so far were saved.")
    }

    @Test("A selected device that wasn't Armed and goes away is quietly deselected")
    func unarmedSelectionThatVanishesIsCleared() {
        let change = InputDeviceChange.decide(
            old: [interface, mic], new: [mic],
            selectedID: "usb2", armed: nil, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: nil, action: .none, stopsTake: false, message: nil))
    }

    @Test("The Armed device changing sample rate re-arms it")
    func sampleRateChangeReArms() {
        let xr18At44 = InputDeviceInfo(id: "xr18", name: "XR18", inputChannelCount: 18, sampleRate: 44_100)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18At44, mic],
            selectedID: "xr18", armed: xr18, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .arm, stopsTake: false, message: nil))
    }

    @Test("The Armed device changing sample rate during a Take stops the Take, re-arms and says so")
    func sampleRateChangeDuringTake() {
        let xr18At44 = InputDeviceInfo(id: "xr18", name: "XR18", inputChannelCount: 18, sampleRate: 44_100)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18At44, mic],
            selectedID: "xr18", armed: xr18, isRecording: true)

        #expect(change.selectedID == "xr18")
        #expect(change.action == .arm)
        #expect(change.stopsTake)
        #expect(change.message == "XR18 changed to 44.1 kHz during the Take. Recording stopped and the Stems recorded so far were saved. Press record to start a new Take.")
    }

    @Test("The Armed device changing its channel count re-arms it")
    func channelCountChangeReArms() {
        let xr18Fewer = InputDeviceInfo(id: "xr18", name: "XR18", inputChannelCount: 12, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18Fewer, mic],
            selectedID: "xr18", armed: xr18, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .arm, stopsTake: false, message: nil))
    }
}

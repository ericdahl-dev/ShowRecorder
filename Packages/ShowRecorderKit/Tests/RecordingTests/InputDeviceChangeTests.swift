import Recording
import Testing

@Suite("Input device list changes")
struct InputDeviceChangeTests {
    let mic = InputDeviceInfo(id: "mic", name: "MacBook Pro Microphone", inputChannelCount: 1, sampleRate: 48_000)
    let xr18 = InputDeviceInfo(id: "xr18", name: "XR18", inputChannelCount: 18, sampleRate: 48_000)
    let interface = InputDeviceInfo(id: "usb2", name: "USB Interface", inputChannelCount: 2, sampleRate: 48_000)

    @Test("The Ready selection is kept when another device appears")
    func keepsSelectionWhenAnotherDeviceAppears() {
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18, mic, interface],
            selectedID: "xr18", ready: xr18, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .none, stopsTake: false, message: nil))
    }

    @Test("Unplugging the Ready device stands down and says so")
    func unpluggingReadyDeviceStandsDown() {
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [mic],
            selectedID: "xr18", ready: xr18, isRecording: false)

        #expect(change.selectedID == nil)
        #expect(change.action == .standDown)
        #expect(!change.stopsTake)
        #expect(change.message == "XR18 was disconnected, so the recorder is no longer Ready. Reconnect it or choose another input.")
    }

    @Test("Unplugging the Ready device during a Take stops the Take and says so")
    func unpluggingDuringTakeStopsIt() {
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [mic],
            selectedID: "xr18", ready: xr18, isRecording: true)

        #expect(change.selectedID == nil)
        #expect(change.action == .standDown)
        #expect(change.stopsTake)
        #expect(change.message == "XR18 was disconnected during the Take. Recording stopped and the Stems recorded so far were saved.")
    }

    @Test("A multichannel device that appears while nothing is Ready is selected and Ready")
    func fullDeviceAppearingWhileNothingReadyIsReady() {
        let change = InputDeviceChange.decide(
            old: [mic], new: [xr18, mic],
            selectedID: nil, ready: nil, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .getReady, stopsTake: false, message: nil))
    }

    @Test("A multichannel device that appears while a built-in mic is Ready takes over")
    func fullDeviceReplacesSmallReadyDevice() {
        let change = InputDeviceChange.decide(
            old: [mic], new: [xr18, mic],
            selectedID: "mic", ready: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .getReady, stopsTake: false, message: nil))
    }

    @Test("A multichannel device of any size takes over from a built-in mic", arguments: [8, 16, 18, 32])
    func anyMultichannelDeviceTakesOver(channels: Int) {
        let device = InputDeviceInfo(id: "multi", name: "Interface", inputChannelCount: channels, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [mic], new: [device, mic],
            selectedID: "mic", ready: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "multi", action: .getReady, stopsTake: false, message: nil))
    }

    @Test("A stereo interface that appears doesn't take over from a built-in mic")
    func stereoDoesNotTakeOver() {
        let change = InputDeviceChange.decide(
            old: [mic], new: [mic, interface],
            selectedID: "mic", ready: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "mic", action: .none, stopsTake: false, message: nil))
    }

    @Test("A bigger device that appears doesn't move a Ready multichannel device")
    func biggerDeviceDoesNotReplaceMultichannel() {
        let x32 = InputDeviceInfo(id: "x32", name: "X-USB", inputChannelCount: 32, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [x32, xr18, mic],
            selectedID: "xr18", ready: xr18, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .none, stopsTake: false, message: nil))
    }

    @Test("When several multichannel devices appear at once, the one with the most channels is Ready")
    func mostChannelsWinsAmongArrivals() {
        let eight = InputDeviceInfo(id: "eight", name: "8-in", inputChannelCount: 8, sampleRate: 48_000)
        let x32 = InputDeviceInfo(id: "x32", name: "X-USB", inputChannelCount: 32, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [mic], new: [eight, mic, x32],
            selectedID: "mic", ready: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "x32", action: .getReady, stopsTake: false, message: nil))
    }

    @Test("A running Take is never moved to a device that appears")
    func takeIsNotMovedToNewDevice() {
        let change = InputDeviceChange.decide(
            old: [mic], new: [xr18, mic],
            selectedID: "mic", ready: mic, isRecording: true)

        #expect(change == InputDeviceChange(selectedID: "mic", action: .none, stopsTake: false, message: nil))
    }

    @Test("A smaller device the operator chose is kept when the multichannel device was already there")
    func operatorChoiceKeptWhenFullDeviceWasPresent() {
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18, mic, interface],
            selectedID: "mic", ready: mic, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "mic", action: .none, stopsTake: false, message: nil))
    }

    @Test("If the Ready device goes and a multichannel device arrives at once, the new one is Ready and the loss is still reported")
    func swapInOneChange() {
        let mr18 = InputDeviceInfo(id: "mr18", name: "MR18", inputChannelCount: 18, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [mr18, mic],
            selectedID: "xr18", ready: xr18, isRecording: true)

        #expect(change.selectedID == "mr18")
        #expect(change.action == .getReady)
        #expect(change.stopsTake)
        #expect(change.message == "XR18 was disconnected during the Take. Recording stopped and the Stems recorded so far were saved.")
    }

    @Test("A selected device that wasn't Ready and goes away is quietly deselected")
    func notReadySelectionThatVanishesIsCleared() {
        let change = InputDeviceChange.decide(
            old: [interface, mic], new: [mic],
            selectedID: "usb2", ready: nil, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: nil, action: .none, stopsTake: false, message: nil))
    }

    @Test("The Ready device changing sample rate gets it ready again")
    func sampleRateChangeGetsReadyAgain() {
        let xr18At44 = InputDeviceInfo(id: "xr18", name: "XR18", inputChannelCount: 18, sampleRate: 44_100)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18At44, mic],
            selectedID: "xr18", ready: xr18, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .getReady, stopsTake: false, message: nil))
    }

    @Test("The Ready device changing sample rate during a Take stops the Take, gets ready again and says so")
    func sampleRateChangeDuringTake() {
        let xr18At44 = InputDeviceInfo(id: "xr18", name: "XR18", inputChannelCount: 18, sampleRate: 44_100)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18At44, mic],
            selectedID: "xr18", ready: xr18, isRecording: true)

        #expect(change.selectedID == "xr18")
        #expect(change.action == .getReady)
        #expect(change.stopsTake)
        #expect(change.message == "XR18 changed to 44.1 kHz during the Take. Recording stopped and the Stems recorded so far were saved. Press record to start a new Take.")
    }

    @Test("The Ready device changing its channel count gets it ready again")
    func channelCountChangeGetsReadyAgain() {
        let xr18Fewer = InputDeviceInfo(id: "xr18", name: "XR18", inputChannelCount: 12, sampleRate: 48_000)
        let change = InputDeviceChange.decide(
            old: [xr18, mic], new: [xr18Fewer, mic],
            selectedID: "xr18", ready: xr18, isRecording: false)

        #expect(change == InputDeviceChange(selectedID: "xr18", action: .getReady, stopsTake: false, message: nil))
    }
}

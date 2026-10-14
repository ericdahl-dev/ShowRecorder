@testable import Recording
import Testing

/// Auto-gain stays out of TestFlight and the App Store until it has run on a real desk with real audio (Eric,
/// 2026-10-12, v1.1.1): Debug builds only.
@Suite("Auto-gain availability")
struct AutoGainAvailabilityTests {
    @Test("Offered in a Debug build only, whatever the distribution")
    func debugOnly() {
        #expect(AutoGainAvailability.isAvailable(isDebugBuild: true))
        #expect(!AutoGainAvailability.isAvailable(isDebugBuild: false))
    }

    @Test("Auto-gain says why it can't run: a Take running first, then no Mixer Link, then a Mixer whose gain can't be set")
    func whyNot() {
        #expect(AutoGainAvailability.whyNot(hasMixerLink: true, canSetGain: true, isRecording: false) == nil)
        #expect(AutoGainAvailability.whyNot(hasMixerLink: true, canSetGain: true, isRecording: true) == .takeRunning)
        #expect(AutoGainAvailability.whyNot(hasMixerLink: false, canSetGain: false, isRecording: true) == .takeRunning)
        #expect(AutoGainAvailability.whyNot(hasMixerLink: false, canSetGain: false, isRecording: false) == .noMixerLink)
        #expect(AutoGainAvailability.whyNot(hasMixerLink: true, canSetGain: false, isRecording: false) == .cantSetGain)
    }

    @Test("Each reason says what to do, in plain words")
    func messages() {
        #expect(AutoGainAvailability.Unavailable.takeRunning.message.contains("Stop the Take"))
        #expect(AutoGainAvailability.Unavailable.noMixerLink.message.contains("Settings › Mixer Link"))
        #expect(!AutoGainAvailability.Unavailable.cantSetGain.message.isEmpty)
    }

    @Test("While Mixer Link is still connecting, it says so instead of asking to connect")
    func connecting() {
        #expect(AutoGainAvailability.whyNot(hasMixerLink: false, isConnecting: true, canSetGain: false, isRecording: false) == .connecting)
        #expect(AutoGainAvailability.whyNot(hasMixerLink: false, isConnecting: true, canSetGain: false, isRecording: true) == .takeRunning)
        #expect(AutoGainAvailability.Unavailable.connecting.message.contains("Connecting"))
    }

    @Test("With the Link on another Mixer than the Armed one, it says which instead of asking to connect, a Take still first (#647)")
    func otherMixerLinked() {
        #expect(AutoGainAvailability.whyNot(hasMixerLink: false, canSetGain: false, isRecording: false, otherMixer: "FOH (XR18)") == .otherMixerLinked("FOH (XR18)"))
        #expect(AutoGainAvailability.whyNot(hasMixerLink: false, canSetGain: false, isRecording: true, otherMixer: "FOH (XR18)") == .takeRunning)
        #expect(AutoGainAvailability.Unavailable.otherMixerLinked("FOH (XR18)").message == "The Mixer Link is on FOH (XR18), not the Armed Mixer. Connect to the Armed Mixer in Settings › Mixer Link first.")
    }
}

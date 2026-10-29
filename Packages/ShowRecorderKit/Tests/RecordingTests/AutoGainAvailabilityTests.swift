@testable import Recording
import Testing

/// Auto-gain is offered in every build, App Store included (Eric, 2026-10-29), after his live XR18 test (2026-10-14).
@Suite("Auto-gain availability")
struct AutoGainAvailabilityTests {
    @Test("Offered everywhere: Debug, TestFlight, the App Store, and before StoreKit has answered")
    func everyone() {
        #expect(AutoGainAvailability.isAvailable(isDebugBuild: true, environment: nil))
        #expect(AutoGainAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
        #expect(AutoGainAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(AutoGainAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(AutoGainAvailability.isAvailable(isDebugBuild: false, environment: nil))
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

    @Test("With the Link on another Mixer than the Ready one, it says which instead of asking to connect, a Take still first (#647)")
    func otherMixerLinked() {
        #expect(AutoGainAvailability.whyNot(hasMixerLink: false, canSetGain: false, isRecording: false, otherMixer: "FOH (XR18)") == .otherMixerLinked("FOH (XR18)"))
        #expect(AutoGainAvailability.whyNot(hasMixerLink: false, canSetGain: false, isRecording: true, otherMixer: "FOH (XR18)") == .takeRunning)
        #expect(AutoGainAvailability.Unavailable.otherMixerLinked("FOH (XR18)").message == "The Mixer Link is on FOH (XR18), not the Mixer you're recording from. Connect to that Mixer in Settings › Mixer Link first.")
    }

    @Test("On Free auto-gain says it's Pro, after a running Take and before any Mixer Link reason (#705)")
    func needsPro() {
        #expect(AutoGainAvailability.whyNot(hasMixerLink: true, canSetGain: true, isRecording: false, allowed: false) == .needsPro)
        #expect(AutoGainAvailability.whyNot(hasMixerLink: false, canSetGain: false, isRecording: false, allowed: false) == .needsPro)
        #expect(AutoGainAvailability.whyNot(hasMixerLink: true, canSetGain: true, isRecording: true, allowed: false) == .takeRunning)
        #expect(AutoGainAvailability.Unavailable.needsPro.message == "Auto-gain is part of Pro. Get it in Settings › Pro.")
    }
}

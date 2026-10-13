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
}


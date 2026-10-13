@testable import Recording
import Testing

/// When the record screen offers auto-gain (#155, #393): never during a Take, since the recorded level would jump
/// even with the mix kept the same.
@Suite("Auto-gain offer")
struct AutoGainOfferTests {
    @Test("Offered with Mixer Link on a mixer that can set gain, between Takes; never during a Take")
    func notDuringATake() {
        #expect(AutoGainAvailability.isOffered(available: true, mixerLinkOffered: true, canSetGain: true, isRecording: false))
        #expect(!AutoGainAvailability.isOffered(available: true, mixerLinkOffered: true, canSetGain: true, isRecording: true))
    }

    @Test("Not offered where it isn't available, without Mixer Link, or on a mixer that can't set gain")
    func needsEverything() {
        #expect(!AutoGainAvailability.isOffered(available: false, mixerLinkOffered: true, canSetGain: true, isRecording: false))
        #expect(!AutoGainAvailability.isOffered(available: true, mixerLinkOffered: false, canSetGain: true, isRecording: false))
        #expect(!AutoGainAvailability.isOffered(available: true, mixerLinkOffered: true, canSetGain: false, isRecording: false))
    }
}

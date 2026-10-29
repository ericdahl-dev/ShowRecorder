@testable import Recording
import Testing

/// When the record screen shows the Gain button (#155): with an X Air or X32 Ready, even when auto-gain can't run, so
/// its sheet can say why (Eric, 2026-10-13). It never runs during a Take (#393): `whyNot` says `.takeRunning`.
@Suite("Auto-gain offer")
struct AutoGainOfferTests {
    @Test("The Gain button shows where auto-gain is available with an X Air or X32 Ready")
    func shown() {
        #expect(AutoGainAvailability.isOffered(available: true, mixerLinkOffered: true))
        #expect(!AutoGainAvailability.isOffered(available: false, mixerLinkOffered: true))
        #expect(!AutoGainAvailability.isOffered(available: true, mixerLinkOffered: false))
    }

    @Test("Shown during a Take, but it can't run then: the sheet says why")
    func duringATakeShownNotRun() {
        #expect(AutoGainAvailability.isOffered(available: true, mixerLinkOffered: true))
        #expect(AutoGainAvailability.whyNot(hasMixerLink: true, canSetGain: true, isRecording: true) == .takeRunning)
    }
}

@testable import Recording
import Testing

/// What VoiceOver says for a meter: coarse enough that it doesn't change 30 times a second (#249).
@Suite("Meter speech")
struct MeterSpeechTests {
    @Test("A meter is read by zone, not by a dB number that changes every frame")
    func zonesNotNumbers() {
        #expect(MeterSpeech.spoken(zone: .low, silent: false, peakIsHot: false, clipped: false) == "Below the target")
        #expect(MeterSpeech.spoken(zone: .onTarget, silent: false, peakIsHot: false, clipped: false) == "On target")
        #expect(MeterSpeech.spoken(zone: .hot, silent: false, peakIsHot: false, clipped: false) == "Above the target")
        #expect(MeterSpeech.spoken(zone: .low, silent: true, peakIsHot: false, clipped: false) == "Silent")
    }

    @Test("Near clipping and a held clip mark come first, since they need action")
    func clipFirst() {
        #expect(MeterSpeech.spoken(zone: .hot, silent: false, peakIsHot: true, clipped: false) == "Near clipping. Above the target")
        #expect(MeterSpeech.spoken(zone: .onTarget, silent: false, peakIsHot: true, clipped: true) == "Clipped. Near clipping. On target")
    }
}

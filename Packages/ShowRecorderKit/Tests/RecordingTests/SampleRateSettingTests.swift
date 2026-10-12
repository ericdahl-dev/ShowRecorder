import Foundation
@testable import Recording
import Testing

/// Recording at the input's sample rate, 96 kHz included (#195). Above 48 kHz is Pro (ADR 0004).
@Suite("Sample rate setting")
struct SampleRateSettingTests {
    let rates = [44_100, 48_000, 96_000]

    @Test("The choice is kept on the device; with nothing stored it is the platform's default (the interface's rate on a Mac, 48 kHz elsewhere)")
    func stored() {
        let defaults = UserDefaults(suiteName: "SampleRateSettingTests-\(UUID().uuidString)")!
        #expect(SampleRateSetting.load(from: defaults, platformDefault: nil) == nil)
        #expect(SampleRateSetting.load(from: defaults, platformDefault: 48_000) == 48_000)
        SampleRateSetting.save(96_000, to: defaults)
        #expect(SampleRateSetting.load(from: defaults, platformDefault: nil) == 96_000)
        SampleRateSetting.save(nil, to: defaults)
        #expect(SampleRateSetting.load(from: defaults, platformDefault: 48_000) == nil)
    }

    @Test("The rate to switch the input to, or nil to leave it: the choice when the input offers it and it differs")
    func rateToSet() {
        #expect(SampleRateSetting.rateToSet(chosen: nil, available: rates, current: 96_000, capAt48k: false) == nil)
        #expect(SampleRateSetting.rateToSet(chosen: 48_000, available: rates, current: 96_000, capAt48k: false) == 48_000)
        #expect(SampleRateSetting.rateToSet(chosen: 96_000, available: rates, current: 48_000, capAt48k: false) == 96_000)
        #expect(SampleRateSetting.rateToSet(chosen: 96_000, available: rates, current: 96_000, capAt48k: false) == nil)
        #expect(SampleRateSetting.rateToSet(chosen: 192_000, available: rates, current: 48_000, capAt48k: false) == nil, "not offered: leave it")
    }

    @Test("Free (once Pro is offered) records at up to 48 kHz: a higher choice or interface rate comes down to 48 kHz when the input offers it")
    func freeCap() {
        #expect(SampleRateSetting.rateToSet(chosen: 96_000, available: rates, current: 48_000, capAt48k: true) == nil)
        #expect(SampleRateSetting.rateToSet(chosen: 96_000, available: rates, current: 96_000, capAt48k: true) == 48_000)
        #expect(SampleRateSetting.rateToSet(chosen: nil, available: rates, current: 96_000, capAt48k: true) == 48_000)
        #expect(SampleRateSetting.rateToSet(chosen: nil, available: [96_000], current: 96_000, capAt48k: true) == nil, "no 48 kHz on offer: record what there is")
        #expect(License(proOffered: true, tier: .free, trialStarted: false, freeChoice: []).capsAt48k)
        #expect(!License(proOffered: false, tier: .free, trialStarted: false, freeChoice: []).capsAt48k)
        #expect(!License(proOffered: true, tier: .trial(daysLeft: 3), trialStarted: true, freeChoice: []).capsAt48k)
    }

    @Test("The picker's labels")
    func labels() {
        #expect(SampleRateSetting.label(nil, current: 96_000) == "Interface (96 kHz)")
        #expect(SampleRateSetting.label(44_100, current: nil) == "44.1 kHz")
        #expect(SampleRateSetting.label(48_000, current: nil) == "48 kHz")
    }

    @Test("A mixer dictates its rate: an input that offers only one rate is never switched, and the picker offers only that")
    func mixerDictates() {
        #expect(SampleRateSetting.rateToSet(chosen: 96_000, available: [48_000], current: 48_000, capAt48k: false) == nil)
        #expect(SampleRateSetting.choices(available: [48_000]) == [nil])
        #expect(SampleRateSetting.choices(available: [44_100, 48_000, 96_000]) == [nil, 44_100, 48_000, 96_000])
    }
}

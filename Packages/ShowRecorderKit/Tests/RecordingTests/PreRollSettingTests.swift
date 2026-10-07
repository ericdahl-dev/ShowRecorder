import Foundation
@testable import Recording
import Testing

@Suite("Pre-roll setting")
struct PreRollSettingTests {
    /// A defaults store that is thrown away with the test.
    func defaults() -> UserDefaults {
        let name = "PreRollSettingTests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    @Test("Unset, it is 10 seconds")
    func defaultsToTen() {
        #expect(PreRollSetting.load(from: defaults()) == 10)
        #expect(PreRollSetting.defaultSeconds == 10)
    }

    @Test("What was saved is read back, including Off")
    func roundTrip() {
        let store = defaults()
        for seconds in PreRollSetting.choices {
            PreRollSetting.save(seconds, to: store)
            #expect(PreRollSetting.load(from: store) == seconds)
        }
        #expect(PreRollSetting.choices.contains(0))
        #expect(PreRollSetting.choices.contains(10))
    }

    @Test("A stored value that isn't one of the choices falls back to the default")
    func unknownValue() {
        let store = defaults()
        store.set(7.5, forKey: PreRollSetting.key)
        #expect(PreRollSetting.load(from: store) == 10)
        store.set(-3.0, forKey: PreRollSetting.key)
        #expect(PreRollSetting.load(from: store) == 10)
    }

    @Test("The memory it needs grows with the length, channels and sample rate, and is nothing when off")
    func memory() {
        let tenSeconds = PreRollSetting.memoryBytes(seconds: 10, channelCount: 18, sampleRate: 48_000)
        // 10 s plus the second of margin, in 4-byte samples.
        #expect(tenSeconds == 11 * 48_000 * 18 * 4)
        #expect(PreRollSetting.memoryBytes(seconds: 0, channelCount: 18, sampleRate: 48_000) == 0)
        #expect(PreRollSetting.memoryBytes(seconds: 10, channelCount: 36, sampleRate: 48_000) == tenSeconds * 2)
        #expect(PreRollSetting.memoryBytes(seconds: 10, channelCount: 18, sampleRate: 96_000) == tenSeconds * 2)
    }
}

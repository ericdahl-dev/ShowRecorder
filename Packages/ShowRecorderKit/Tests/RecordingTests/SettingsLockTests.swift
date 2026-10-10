@testable import Recording
import Testing

/// Which settings can be changed while a Take is running.
@Suite("Settings lock")
struct SettingsLockTests {
    @Test("During a Take the input, Pre-roll, Drive and Mixer Link are locked: changing them could disturb the recording")
    func lockedDuringATake() {
        for item in [SettingsItem.input, .preRoll, .drive, .mixerLink] {
            #expect(SettingsLock.isLocked(item, isRecording: true), "\(item)")
        }
    }

    @Test("Appearance, the transport side and Channel names stay usable during a Take")
    func openDuringATake() {
        for item in [SettingsItem.appearance, .transportSide, .channelNames] {
            #expect(!SettingsLock.isLocked(item, isRecording: true), "\(item)")
        }
    }

    @Test("Nothing is locked when no Take is running")
    func nothingLockedOtherwise() {
        for item in SettingsItem.allCases { #expect(!SettingsLock.isLocked(item, isRecording: false), "\(item)") }
    }
}

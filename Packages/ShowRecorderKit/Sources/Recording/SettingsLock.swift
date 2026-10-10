/// A setting on the Settings screen.
public enum SettingsItem: CaseIterable, Sendable {
    case input, preRoll, drive, mixerLink
    case appearance, transportSide, channelNames
}

/// Which settings can't be changed during a Take. The first four could disturb the recording (re-arming, a new
/// Drive folder, the Mixer Link); how the screen looks, which side the buttons are on and naming channels can't.
public enum SettingsLock {
    public static func isLocked(_ item: SettingsItem, isRecording: Bool) -> Bool {
        guard isRecording else { return false }
        switch item {
        case .input, .preRoll, .drive, .mixerLink: return true
        case .appearance, .transportSide, .channelNames: return false
        }
    }
}

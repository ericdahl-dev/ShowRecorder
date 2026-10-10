/// A setting on the Settings screen.
public enum SettingsItem: CaseIterable, Sendable {
    case input, preRoll, drive, mixerLink, pro
    case appearance, transportSide, channelNames
}

/// Which settings can't be changed during a Take. The first four could disturb the recording (re-arming, a new
/// Drive folder, the Mixer Link), and Pro (buying, restoring and the Free channel choice) is hidden so nothing about the
/// license is in front of the operator mid-show; how the screen looks, which side the buttons are on and naming channels can't.
public enum SettingsLock {
    public static func isLocked(_ item: SettingsItem, isRecording: Bool) -> Bool {
        guard isRecording else { return false }
        switch item {
        case .input, .preRoll, .drive, .mixerLink, .pro: return true
        case .appearance, .transportSide, .channelNames: return false
        }
    }
}

/// A setting on the Settings screen.
public enum SettingsItem: CaseIterable, Sendable {
    case input, preRoll, drive, recordTo, mixerLink, pro
    case appearance, transportSide, channelNames
}

/// Which settings can't be changed during a Take. The first five could disturb the recording (getting ready again, a new
/// Drive folder, where Takes go, the Mixer Link), and Pro (buying, restoring and the Free channel choice) is hidden so nothing about the
/// license is in front of the operator mid-show; how the screen looks, which side the buttons are on and naming channels can't.
public enum SettingsLock {
    public static func isLocked(_ item: SettingsItem, isRecording: Bool) -> Bool {
        guard isRecording else { return false }
        switch item {
        case .input, .preRoll, .drive, .recordTo, .mixerLink, .pro: return true
        case .appearance, .transportSide, .channelNames: return false
        }
    }
}

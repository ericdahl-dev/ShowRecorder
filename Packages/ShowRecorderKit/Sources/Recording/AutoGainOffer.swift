extension AutoGainAvailability {
    /// Whether the record screen offers auto-gain (#155): where it is available, with Mixer Link on a mixer that can
    /// set gain, and never during a Take (#393): the recorded level would jump even with the mix kept the same.
    public static func isOffered(available: Bool, mixerLinkOffered: Bool, canSetGain: Bool, isRecording: Bool) -> Bool {
        available && mixerLinkOffered && canSetGain && !isRecording
    }
}

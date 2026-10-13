extension AutoGainAvailability {
    /// Whether the record screen shows the Gain button (#155): where auto-gain is available, with an X Air or X32 Armed.
    /// It shows even when auto-gain can't run (a Take, no Mixer Link, a Mixer whose gain can't be set), so its sheet
    /// says why (Eric, 2026-10-13); `whyNot` keeps it from running then, and never during a Take (#393).
    public static func isOffered(available: Bool, mixerLinkOffered: Bool) -> Bool {
        available && mixerLinkOffered
    }
}

/// Where auto-gain (#155) is offered: Debug builds only, until it has run on a real desk with real audio. Hidden in
/// TestFlight and the App Store (Eric, 2026-10-12, for v1.1.1). Opening it up is this one rule.
public enum AutoGainAvailability {
    public static func isAvailable(isDebugBuild: Bool = LaunchFlags.isDebugBuild) -> Bool {
        isDebugBuild
    }
}

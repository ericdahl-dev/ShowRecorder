/// Where a 2-input interface records its Take as one stereo file named "Stereo" instead of two mono Stems (#1088): Debug
/// and TestFlight builds, never the App Store build, until Eric has recorded a Take with it on a device (Eric, 2026-11-07).
/// Where it is off, a 2-input interface records two mono Stems as before. Opening it up is this one rule.
public enum StereoPairAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer offers it in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

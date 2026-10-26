/// Where "Record to the Drive only" (#196, ADR 0006) is offered: Debug and TestFlight builds, so Eric can test it on
/// his rig (pull the Drive mid-Take), never the App Store build until that test passes (Eric, 2026-10-13). Opening it
/// up is this one rule. The environment is the one `DemoSignalAvailability` resolves from StoreKit.
public enum DriveOnlyAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer offers it in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

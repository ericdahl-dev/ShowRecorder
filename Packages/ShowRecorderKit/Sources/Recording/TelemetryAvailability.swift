/// Where crash reports and usage (ADR 0007, #1026) are sent: Debug and TestFlight builds, so Eric can check on a device
/// that a test crash and the events arrive and that the switch stops them. Never the App Store build until then, and
/// until the App Store privacy label says so. Opening it up is this one rule. The environment is the one
/// `DemoSignalAvailability` resolves from StoreKit.
public enum TelemetryAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer sends in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

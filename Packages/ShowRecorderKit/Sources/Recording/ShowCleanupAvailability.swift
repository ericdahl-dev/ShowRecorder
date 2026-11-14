/// Where the Shows list's Select mode, which deletes several Shows at once (#1217), is offered: Debug and TestFlight
/// builds until Eric has tried it on a device.
public enum ShowCleanupAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer offers it in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

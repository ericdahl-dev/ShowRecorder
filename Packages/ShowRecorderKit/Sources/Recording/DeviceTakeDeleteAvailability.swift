/// Where "Delete from iPhone" (#656) is offered: Debug builds only, until Eric has tried it on a device with a real kept Take
/// (2026-10-21); never TestFlight or the App Store build before that. It deletes the Device's copy of a Take, so opening it up is
/// this one rule. The environment is the one `DemoSignalAvailability` resolves from StoreKit.
public enum DeviceTakeDeleteAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugOnly

    /// `environment` is not read at the Debug only level.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

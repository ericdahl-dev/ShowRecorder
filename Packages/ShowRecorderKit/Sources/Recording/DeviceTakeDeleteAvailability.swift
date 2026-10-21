/// Where "Delete from iPhone" (#656) is offered: Debug builds only, until Eric has tried it on a device with a real kept Take
/// (2026-10-21); never TestFlight or the App Store build before that. It deletes the Device's copy of a Take, so opening it up is
/// this one rule. The environment is the one `DemoSignalAvailability` resolves from StoreKit.
public enum DeviceTakeDeleteAvailability {
    /// `environment` is not used while the rule is Debug only; moving it up to TestFlight (`environment == .sandbox`) is the next level.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        isDebugBuild
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return isAvailable(isDebugBuild: isDebugBuild, environment: DemoSignalAvailability.environment)
    }
}

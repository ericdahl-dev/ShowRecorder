/// Where "Delete from iPhone" (#656) is offered: Debug and TestFlight builds, until Eric has tried it on a device with a real
/// kept Take (2026-10-20); never the App Store build before that. It deletes the Device's copy of a Take, so opening it up is
/// this one rule. The environment is the one `DemoSignalAvailability` resolves from StoreKit.
public enum DeviceTakeDeleteAvailability {
    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer offers it in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        isDebugBuild || environment == .sandbox
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

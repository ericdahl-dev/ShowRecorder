/// Where "Record to the Drive only" (#196, ADR 0006) is offered: Debug and TestFlight builds, so Eric can test it on
/// his rig (pull the Drive mid-Take), never the App Store build until that test passes (Eric, 2026-10-13). Opening it
/// up is this one rule. The environment is the one `DemoSignalAvailability` resolves from StoreKit.
public enum DriveOnlyAvailability {
    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer offers it in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        isDebugBuild || environment == .sandbox
    }
}

/// Where the iPhone stops a Take with a 1 s hold instead of a tap and a confirmation (#753): Debug builds and
/// TestFlight builds, until Eric has tried it on a device and it moves up a level (its own one-line PR). The App Store
/// build keeps tap and confirm. The Mac keeps click and confirm whatever this says.
///
/// It reads the same StoreKit environment as `DemoSignalAvailability`, which `resolveEnvironment()` fills in, so a
/// Release build keeps it off until TestFlight is confirmed.
public enum HoldToStopAvailability {
    /// `environment` is nil until the answer has arrived.
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

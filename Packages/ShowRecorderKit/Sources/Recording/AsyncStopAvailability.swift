/// Where the asynchronous Stop (#652, part A) is used: Debug builds only, until Eric has tried it on a device and it
/// moves up a level (its own one-line PR). `Recorder.stopTake` asks at each Stop, and finishes the Take off the main actor
/// when it is on.
public enum AsyncStopAvailability {
    /// `environment` is nil until StoreKit has answered. At the Debug-only level it is not read; moving the feature to Debug +
    /// TestFlight is `isDebugBuild || environment == .sandbox`, as for `DriveOnlyAvailability`.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment? = nil) -> Bool {
        isDebugBuild
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return isAvailable(isDebugBuild: isDebugBuild, environment: DemoSignalAvailability.environment)
    }
}

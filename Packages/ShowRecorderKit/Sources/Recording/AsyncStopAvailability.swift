/// Where the asynchronous Stop (#652, part A) is used: Debug builds only, until Eric has tried it on a device and it
/// moves up a level (its own one-line PR). `Recorder.stopTake` asks at each Stop, and finishes the Take off the main actor
/// when it is on.
public enum AsyncStopAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugOnly

    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment? = nil) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

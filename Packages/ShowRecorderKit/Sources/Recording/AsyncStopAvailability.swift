/// Where the asynchronous Stop (#652, part A) is used, with its progress-based wait for a slow Drive (#817): Debug and
/// TestFlight builds, never the App Store build, so Eric can check it with the slow stick from a TestFlight build
/// (Eric, 2026-11-08). Moving it to every build is its own one-line PR. `Recorder.stopTake` asks at each Stop, and
/// finishes the Take off the main actor when it is on.
public enum AsyncStopAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment? = nil) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

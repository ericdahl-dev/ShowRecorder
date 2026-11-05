/// Where the App Store rating prompt (`RatingPromptPolicy`) is asked: every build (Eric, 2026-11-05). Apple shows nothing
/// in TestFlight and limits it to 3 times a year in the App Store build. The environment is the one
/// `DemoSignalAvailability` resolves from StoreKit.
public enum RatingPromptAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .everyone

    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer asks in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

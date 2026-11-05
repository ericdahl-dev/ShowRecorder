/// Where the App Store rating prompt (`RatingPromptPolicy`) is asked: Debug and TestFlight builds, so Eric can see on a
/// device when it comes. Never the App Store build until then; opening it up is this one rule, in its own PR. The
/// environment is the one `DemoSignalAvailability` resolves from StoreKit.
public enum RatingPromptAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer asks in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

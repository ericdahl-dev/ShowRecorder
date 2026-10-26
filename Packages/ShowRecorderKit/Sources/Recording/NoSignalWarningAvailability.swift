/// Where the "no signal" warning on a Take is shown (#778): Debug builds and TestFlight builds, until Eric has tried it on
/// a device and it moves up a level (its own one-line PR). The App Store build shows no warning.
///
/// It reads the same StoreKit environment as `DemoSignalAvailability`, which `resolveEnvironment()` fills in, so a
/// Release build keeps it off until TestFlight is confirmed.
public enum NoSignalWarningAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until the answer has arrived.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

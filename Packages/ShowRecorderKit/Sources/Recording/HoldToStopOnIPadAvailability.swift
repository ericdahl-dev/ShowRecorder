/// Where the iPad stops a Take with a 1 s hold instead of a tap and a confirmation (#753): Debug builds and TestFlight
/// builds, until someone has tried it on an iPad and it moves up a level (its own one-line PR). The iPhone has its own
/// rule, `HoldToStopAvailability`. The App Store build keeps tap and confirm on the iPad.
///
/// It reads the same StoreKit environment as `DemoSignalAvailability`, which `resolveEnvironment()` fills in, so a
/// Release build keeps it off until TestFlight is confirmed.
public enum HoldToStopOnIPadAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until the answer has arrived.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

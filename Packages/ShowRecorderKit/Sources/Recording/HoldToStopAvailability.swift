/// Where the iPhone stops a Take with a 1 s hold instead of a tap and a confirmation (#753): everyone, since Eric checked
/// it on an iPhone (2026-11-07, TestFlight 1.2.5: a 1 s hold stops, a tap shows "Hold to stop", an early release keeps
/// recording). The iPad has its own rule, `HoldToStopOnIPadAvailability`, until someone tries it on an iPad. The Mac
/// keeps click and confirm whatever this says.
///
/// It reads the same StoreKit environment as `DemoSignalAvailability`, which `resolveEnvironment()` fills in.
public enum HoldToStopAvailability {
    /// Where it is offered on the iPhone.
    public static let level: AvailabilityLevel = .everyone

    /// `environment` is nil until the answer has arrived.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

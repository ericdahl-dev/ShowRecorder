/// Where crash reports and usage (ADR 0007, #1026) are sent: every build (Eric, 2026-11-17), after his TestFlight
/// 1.2.13 check that events arrive and that Settings › Share crash reports and usage stops them. The App Store privacy
/// label and `App/PrivacyInfo.xcprivacy` say so. The environment is the one `DemoSignalAvailability` resolves from
/// StoreKit.
public enum TelemetryAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .everyone

    /// `environment` is nil until StoreKit has answered; at this level every build sends either way.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

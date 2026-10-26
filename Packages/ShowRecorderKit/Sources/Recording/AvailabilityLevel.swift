/// How widely a feature that ships hidden is offered (CLAUDE.md, Eric 2026-10-13). Each feature's availability rule names one
/// of these as its `level`; moving the feature up a level, after Eric has tried it on a device, is that one line (#557).
public enum AvailabilityLevel: CaseIterable, Sendable {
    /// Debug builds only.
    case debugOnly
    /// Debug builds, and TestFlight builds, never the App Store build.
    case debugAndTestFlight
    /// Every build.
    case everyone

    /// `environment` is nil until StoreKit has answered (`DemoSignalAvailability.resolveEnvironment()`); only a sandbox
    /// (TestFlight) answer offers a Debug + TestFlight feature in a Release build.
    public func isOn(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        switch self {
        case .debugOnly: isDebugBuild
        case .debugAndTestFlight: isDebugBuild || environment == .sandbox
        case .everyone: true
        }
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public var isOnInThisBuild: Bool {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return isOn(isDebugBuild: isDebugBuild, environment: DemoSignalAvailability.environment)
    }
}

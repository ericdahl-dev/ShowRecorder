import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Which App Store environment the running build was distributed through.
public enum DistributionEnvironment: Sendable, Equatable {
    /// The App Store build.
    case production
    /// A TestFlight build.
    case sandbox
    /// Anything else (Xcode, local testing, or an environment this app doesn't know).
    case unknown
}

/// Where the Demo signal input is offered: Debug builds, and TestFlight builds, so a tester
/// without a mixer can still record a Take. The App Store build never offers it.
///
/// The environment comes from StoreKit's `AppTransaction`, which is async, so it starts out
/// unknown (no Demo signal in a Release build) and `resolveEnvironment()` fills it in.
public enum DemoSignalAvailability {
    /// `environment` is nil until the answer has arrived. Only a sandbox (TestFlight) answer
    /// offers the Demo signal in a Release build; every other answer, or none, does not.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        isDebugBuild || environment == .sandbox
    }

    private static let resolved = Resolved()

    private final class Resolved: @unchecked Sendable {
        private let lock = NSLock()
        private var value: DistributionEnvironment?
        var environment: DistributionEnvironment? {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    /// The answer for the running app, from what `resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return isAvailable(isDebugBuild: isDebugBuild, environment: resolved.environment)
    }

    /// Asks StoreKit which environment this build came from and remembers it. An unverified or
    /// failed answer is not trusted: it leaves the Demo signal off in a Release build.
    @discardableResult
    public static func resolveEnvironment() async -> DistributionEnvironment {
        let environment = await currentEnvironment()
        resolved.environment = environment
        return environment
    }

    private static func currentEnvironment() async -> DistributionEnvironment {
        #if canImport(StoreKit)
        guard case .verified(let transaction) = try? await AppTransaction.shared else { return .unknown }
        switch transaction.environment {
        case .production: return .production
        case .sandbox: return .sandbox
        default: return .unknown
        }
        #else
        return .unknown
        #endif
    }
}

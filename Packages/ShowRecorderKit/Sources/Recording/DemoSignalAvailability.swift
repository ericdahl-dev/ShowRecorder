import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Which App Store environment the running build was distributed through.
public enum DistributionEnvironment: Sendable, Equatable {
    /// The App Store build.
    case production
    /// A TestFlight build, or (expected) a build under App Review.
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
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until the answer has arrived. Only a sandbox (TestFlight) answer
    /// offers the Demo signal in a Release build; every other answer, or none, does not.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    private static let resolved = Resolved()

    /// What StoreKit has answered so far in this launch. Internal so tests can feed it answers: StoreKit can't run there.
    final class Resolved: @unchecked Sendable {
        private let lock = NSLock()
        private var value: DistributionEnvironment?

        init() {}

        /// The environment kept so far; nil before the first answer.
        var environment: DistributionEnvironment? { lock.withLock { value } }

        /// Takes a fresh answer from StoreKit and returns the environment kept.
        func remember(_ fresh: DistributionEnvironment) -> DistributionEnvironment {
            lock.withLock {
                value = fresh
                return fresh
            }
        }
    }

    /// The environment `resolveEnvironment()` has found so far; nil before it has answered.
    public static var environment: DistributionEnvironment? { resolved.environment }

    /// The answer for the running app, from what `resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }

    /// Asks StoreKit which environment this build came from and remembers it. An unverified or
    /// failed answer is not trusted: it leaves the Demo signal off in a Release build.
    @discardableResult
    public static func resolveEnvironment() async -> DistributionEnvironment {
        resolved.remember(await currentEnvironment())
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

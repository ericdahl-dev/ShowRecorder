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

        /// Takes a fresh answer from StoreKit and returns the environment kept. A failed or unverified answer
        /// (`.unknown`) never replaces a verified `.sandbox` or `.production` found earlier in this launch, so a check
        /// that fails offline doesn't hide the TestFlight features mid-run (#994). A verified answer replaces an earlier
        /// `.unknown`, so a launch that starts offline picks it up once StoreKit answers. Two verified answers that
        /// differ shouldn't happen; the newer one is kept, since StoreKit keeps its own transaction up to date.
        func remember(_ fresh: DistributionEnvironment) -> DistributionEnvironment {
            lock.withLock {
                if fresh != .unknown || value == nil { value = fresh }
                return value ?? fresh
            }
        }
    }

    /// The environment `resolveEnvironment()` has found so far; nil before it has answered.
    public static var environment: DistributionEnvironment? { resolved.environment }

    /// The answer for the running app, from what `resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }

    /// Asks StoreKit which environment this build came from, remembers it, and returns the environment kept (the
    /// same as `environment` afterwards). An unverified or failed answer is not trusted: it leaves the Demo signal off
    /// in a Release build, unless a verified answer arrived earlier in this launch, which it then keeps.
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

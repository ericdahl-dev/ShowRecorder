@testable import Recording
import Testing

/// Selecting several Shows and deleting them at once (#1217) is offered in Debug and TestFlight builds until Eric has
/// tried it on a device. Opening it up is this one rule.
@Suite("Show clean-up availability")
struct ShowCleanupAvailabilityTests {
    @Test("Debug builds offer it whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(ShowCleanupAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds offer it")
    func testFlightBuild() {
        #expect(ShowCleanupAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build does not")
    func appStoreBuild() {
        #expect(!ShowCleanupAvailability.isAvailable(isDebugBuild: false, environment: .production))
    }

    @Test("A Release build whose environment is unknown or not yet answered does not")
    func unknownEnvironment() {
        #expect(!ShowCleanupAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(!ShowCleanupAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
    }
}

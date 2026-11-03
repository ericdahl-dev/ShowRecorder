@testable import Recording
import Testing

/// Crash reports and usage (ADR 0007, #1026) are offered in Debug and TestFlight builds first, so Eric can check on a
/// device that a test crash and the events arrive and that the switch stops them. Opening it up is this one rule.
@Suite("Telemetry availability")
struct TelemetryAvailabilityTests {
    @Test("Debug builds send whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(TelemetryAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds send")
    func testFlightBuild() {
        #expect(TelemetryAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build does not, until the privacy label says it does")
    func appStoreBuild() {
        #expect(!TelemetryAvailability.isAvailable(isDebugBuild: false, environment: .production))
    }

    @Test("A Release build whose environment is unknown or not yet answered does not")
    func unknownEnvironment() {
        #expect(!TelemetryAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(!TelemetryAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
    }
}

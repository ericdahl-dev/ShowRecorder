@testable import Recording
import Testing

/// Crash reports and usage (ADR 0007, #1026) are offered in every build (Eric, 2026-11-17), after his TestFlight 1.2.13
/// check that events arrive and that Settings › Share crash reports and usage stops them.
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

    @Test("The App Store (production) build sends")
    func appStoreBuild() {
        #expect(TelemetryAvailability.isAvailable(isDebugBuild: false, environment: .production))
    }

    @Test("A Release build sends before StoreKit has said where it came from")
    func unknownEnvironment() {
        #expect(TelemetryAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(TelemetryAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
    }
}

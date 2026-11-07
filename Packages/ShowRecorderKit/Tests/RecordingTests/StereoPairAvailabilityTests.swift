@testable import Recording
import Testing

/// Recording a 2-input interface as one stereo file (#1088) is offered in Debug and TestFlight builds, never the App Store
/// build, until Eric has recorded a Take with it on a device (Eric, 2026-11-07). Opening it up is this one rule.
@Suite("Stereo pair availability")
struct StereoPairAvailabilityTests {
    @Test("It is at the everyone level (#1088)")
    func level() {
        #expect(StereoPairAvailability.level == .everyone)
    }

    @Test("Debug builds offer it whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(StereoPairAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds offer it")
    func testFlightBuild() {
        #expect(StereoPairAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build offers it, and so does a Release build whose environment is unknown or not yet answered")
    func appStoreBuild() {
        #expect(!StereoPairAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(!StereoPairAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(!StereoPairAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }
}

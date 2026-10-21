@testable import Recording
import Testing

/// "Delete from iPhone" (#656) deletes the only copy a Take has on the Device, so it is offered in Debug and TestFlight
/// builds until Eric has tried it on a device (2026-10-20), and never in the App Store build. Opening it up is this one rule.
@Suite("Delete from the Device availability")
struct DeviceTakeDeleteAvailabilityTests {
    @Test("Debug builds offer it whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(DeviceTakeDeleteAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds offer it")
    func testFlightBuild() {
        #expect(DeviceTakeDeleteAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build does not")
    func appStoreBuild() {
        #expect(!DeviceTakeDeleteAvailability.isAvailable(isDebugBuild: false, environment: .production))
    }

    @Test("A Release build whose environment is unknown or not yet answered does not")
    func unknownEnvironment() {
        #expect(!DeviceTakeDeleteAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(!DeviceTakeDeleteAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
    }
}

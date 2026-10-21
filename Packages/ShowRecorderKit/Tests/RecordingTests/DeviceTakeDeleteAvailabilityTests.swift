@testable import Recording
import Testing

/// "Delete from iPhone" (#656) deletes the only copy a Take has on the Device, so it is offered in Debug builds only until
/// Eric has tried it on a device (2026-10-21). Opening it up is this one rule.
@Suite("Delete from the Device availability")
struct DeviceTakeDeleteAvailabilityTests {
    @Test("Debug builds offer it whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(DeviceTakeDeleteAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("No Release build offers it, whatever the environment: not TestFlight, not the App Store")
    func releaseBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(!DeviceTakeDeleteAvailability.isAvailable(isDebugBuild: false, environment: environment))
        }
    }
}

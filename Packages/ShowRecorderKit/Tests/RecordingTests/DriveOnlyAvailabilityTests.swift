@testable import Recording
import Testing

/// "Record to the Drive only" (#196) is offered in Debug and TestFlight builds, so Eric can test it on his rig (pull the
/// Drive mid-Take), and never in the App Store build until that test passes. Opening it up is this one rule.
@Suite("Drive only availability")
struct DriveOnlyAvailabilityTests {
    @Test("Debug builds offer it whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(DriveOnlyAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds offer it")
    func testFlightBuild() {
        #expect(DriveOnlyAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build does not")
    func appStoreBuild() {
        #expect(!DriveOnlyAvailability.isAvailable(isDebugBuild: false, environment: .production))
    }

    @Test("A Release build whose environment is unknown or not yet answered does not")
    func unknownEnvironment() {
        #expect(!DriveOnlyAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(!DriveOnlyAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
    }
}

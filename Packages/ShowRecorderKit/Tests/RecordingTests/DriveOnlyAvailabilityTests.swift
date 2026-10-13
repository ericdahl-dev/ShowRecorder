@testable import Recording
import Testing

/// "Record to the Drive only" (#196) is offered in Debug builds only until it has passed Eric's rig test (pull the
/// Drive mid-Take); opening it to TestFlight is this one rule.
@Suite("Drive only availability")
struct DriveOnlyAvailabilityTests {
    @Test("Offered in a Debug build, never in TestFlight or the App Store")
    func debugOnly() {
        #expect(DriveOnlyAvailability.isAvailable(isDebugBuild: true))
        #expect(!DriveOnlyAvailability.isAvailable(isDebugBuild: false))
    }
}

@testable import Recording
import Testing

/// Auto-gain opens to TestFlight and the App Store once it has passed the live XR18 test with Eric (#155).
@Suite("Auto-gain availability")
struct AutoGainAvailabilityTests {
    @Test("Offered in every build: Debug, TestFlight and the App Store")
    func everyBuild() {
        #expect(AutoGainAvailability.isAvailable(isDebugBuild: true))
        #expect(AutoGainAvailability.isAvailable(isDebugBuild: false))
    }
}

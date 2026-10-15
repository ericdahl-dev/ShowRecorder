import Recording
import Testing

@Suite("Marker button availability")
struct MarkerButtonAvailabilityTests {
    @Test("Debug builds offer the Marker button on the Live Activity whatever the environment")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(MarkerButtonAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds offer it")
    func testFlightBuild() {
        #expect(MarkerButtonAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store build does not, nor a Release build whose environment is unknown or not yet answered")
    func everyoneElse() {
        #expect(!MarkerButtonAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(!MarkerButtonAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(!MarkerButtonAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }
}

@Suite("Marker button availability in this build")
struct MarkerButtonAvailabilityThisBuildTests {
    @Test("A Debug build offers the button before the environment is known; a Release build waits for TestFlight")
    func thisBuild() {
        #if DEBUG
        #expect(MarkerButtonAvailability.isAvailableInThisBuild)
        #else
        #expect(!MarkerButtonAvailability.isAvailableInThisBuild, "no environment resolved in tests")
        #endif
    }
}

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

    @Test("It is at the everyone level (#684)")
    func level() {
        #expect(MarkerButtonAvailability.level == .everyone)
    }

    @Test("The App Store build offers it, and so does a Release build whose environment is unknown or not yet answered")
    func everyoneElse() {
        #expect(MarkerButtonAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(MarkerButtonAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(MarkerButtonAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }
}

@Suite("Marker button availability in this build")
struct MarkerButtonAvailabilityThisBuildTests {
    @Test("Every build offers the button, before the environment is known too")
    func thisBuild() {
        #expect(MarkerButtonAvailability.isAvailableInThisBuild)
    }
}

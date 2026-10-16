import Recording
import Testing

@Suite("Hold to stop availability")
struct HoldToStopAvailabilityTests {
    @Test("Debug builds hold to stop on the iPhone whatever the environment")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(HoldToStopAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds hold to stop")
    func testFlightBuild() {
        #expect(HoldToStopAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store build keeps tap and confirm, as does a Release build whose environment is unknown or not yet answered")
    func everyoneElse() {
        #expect(!HoldToStopAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(!HoldToStopAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(!HoldToStopAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }
}

@Suite("Hold to stop availability in this build")
struct HoldToStopAvailabilityThisBuildTests {
    @Test("A Debug build holds before the environment is known; a Release build waits for TestFlight")
    func thisBuild() {
        #if DEBUG
        #expect(HoldToStopAvailability.isAvailableInThisBuild)
        #else
        #expect(!HoldToStopAvailability.isAvailableInThisBuild, "no environment resolved in tests")
        #endif
    }
}

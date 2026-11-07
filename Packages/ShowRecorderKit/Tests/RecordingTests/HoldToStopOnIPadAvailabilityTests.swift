import Recording
import Testing

/// Hold to stop on the iPad (#753) is offered in Debug and TestFlight builds, never the App Store build, until someone
/// has tried it on an iPad (Eric, 2026-11-07: he has no iPad to check with). Opening it up is this one rule.
@Suite("Hold to stop on iPad availability")
struct HoldToStopOnIPadAvailabilityTests {
    @Test("It is at the Debug and TestFlight level (#753)")
    func level() {
        #expect(HoldToStopOnIPadAvailability.level == .debugAndTestFlight)
    }

    @Test("Debug builds offer it whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(HoldToStopOnIPadAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds offer it")
    func testFlightBuild() {
        #expect(HoldToStopOnIPadAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build keeps tap and confirm, as does a Release build whose environment is unknown or not yet answered")
    func appStoreBuild() {
        #expect(!HoldToStopOnIPadAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(!HoldToStopOnIPadAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(!HoldToStopOnIPadAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }
}

@Suite("Hold to stop on iPad availability in this build")
struct HoldToStopOnIPadAvailabilityThisBuildTests {
    @Test("A Debug build holds before the environment is known; a Release build waits for TestFlight")
    func thisBuild() {
        #if DEBUG
        #expect(HoldToStopOnIPadAvailability.isAvailableInThisBuild)
        #else
        #expect(!HoldToStopOnIPadAvailability.isAvailableInThisBuild, "no environment resolved in tests")
        #endif
    }
}

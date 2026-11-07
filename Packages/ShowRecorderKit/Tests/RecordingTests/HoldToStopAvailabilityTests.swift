import Recording
import Testing

/// Hold to stop on the iPhone (#753) is for everyone since Eric checked it on an iPhone (2026-11-07, TestFlight 1.2.5).
@Suite("Hold to stop availability")
struct HoldToStopAvailabilityTests {
    @Test("It is at the everyone level (#753)")
    func level() {
        #expect(HoldToStopAvailability.level == .everyone)
    }

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

    @Test("The App Store build holds to stop, and so does a Release build whose environment is unknown or not yet answered")
    func appStoreBuild() {
        #expect(HoldToStopAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(HoldToStopAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(HoldToStopAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }
}

@Suite("Hold to stop availability in this build")
struct HoldToStopAvailabilityThisBuildTests {
    @Test("Every build holds to stop on the iPhone, before the environment is known too")
    func thisBuild() {
        #expect(HoldToStopAvailability.isAvailableInThisBuild)
    }
}

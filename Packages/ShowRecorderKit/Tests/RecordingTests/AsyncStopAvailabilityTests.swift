import Recording
import Testing

/// The asynchronous, progress-based Stop (#652, #817) is used in Debug and TestFlight builds, never the App Store build,
/// so Eric can check it with the slow stick from a TestFlight build (Eric, 2026-11-08: no Mac for a Debug build).
/// Opening it up is this one rule.
@Suite("Async Stop availability")
struct AsyncStopAvailabilityTests {
    @Test("It is at the Debug and TestFlight level (#817, #652)")
    func level() {
        #expect(AsyncStopAvailability.level == .debugAndTestFlight)
    }

    @Test("Debug builds use the asynchronous Stop whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(AsyncStopAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds use it")
    func testFlightBuild() {
        #expect(AsyncStopAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build does not")
    func appStoreBuild() {
        #expect(!AsyncStopAvailability.isAvailable(isDebugBuild: false, environment: .production))
    }

    @Test("A Release build whose environment is unknown or not yet answered does not")
    func unknownEnvironment() {
        #expect(!AsyncStopAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(!AsyncStopAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(!AsyncStopAvailability.isAvailable(isDebugBuild: false))
    }

    @Test("This build follows its configuration; a Release build waits for TestFlight")
    func thisBuild() {
        #if DEBUG
        #expect(AsyncStopAvailability.isAvailableInThisBuild)
        #else
        #expect(!AsyncStopAvailability.isAvailableInThisBuild, "no environment resolved in tests")
        #endif
    }
}

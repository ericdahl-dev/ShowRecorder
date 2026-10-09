import Recording
import Testing

@Suite("Demo signal availability")
struct DemoSignalAvailabilityTests {
    @Test("Debug builds offer the Demo signal whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(DemoSignalAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds offer it")
    func testFlightBuild() {
        #expect(DemoSignalAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build does not")
    func appStoreBuild() {
        #expect(!DemoSignalAvailability.isAvailable(isDebugBuild: false, environment: .production))
    }

    @Test("A Release build whose environment is unknown or not yet answered does not")
    func unknownEnvironment() {
        #expect(!DemoSignalAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(!DemoSignalAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
    }
}

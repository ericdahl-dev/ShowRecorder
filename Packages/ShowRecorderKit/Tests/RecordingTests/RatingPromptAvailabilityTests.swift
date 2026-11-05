@testable import Recording
import Testing

/// The App Store rating prompt is asked in Debug and TestFlight builds first, so Eric can see on a device when it comes.
/// Opening it up to the App Store build is this one rule.
@Suite("Rating prompt availability")
struct RatingPromptAvailabilityTests {
    @Test("Debug builds ask whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(RatingPromptAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds ask")
    func testFlightBuild() {
        #expect(RatingPromptAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build does not, until Eric has tried it")
    func appStoreBuild() {
        #expect(!RatingPromptAvailability.isAvailable(isDebugBuild: false, environment: .production))
    }

    @Test("A Release build whose environment is unknown or not yet answered does not")
    func unknownEnvironment() {
        #expect(!RatingPromptAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(!RatingPromptAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
    }
}

@testable import Recording
import Testing

/// The App Store rating prompt is asked in every build (Eric, 2026-11-05). Apple shows nothing in TestFlight and limits
/// it to 3 times a year in the App Store build; `RatingPromptPolicy` decides when to ask.
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

    @Test("The App Store (production) build asks")
    func appStoreBuild() {
        #expect(RatingPromptAvailability.isAvailable(isDebugBuild: false, environment: .production))
    }

    @Test("A Release build asks before StoreKit has said where it came from")
    func unknownEnvironment() {
        #expect(RatingPromptAvailability.isAvailable(isDebugBuild: false, environment: nil))
        #expect(RatingPromptAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
    }
}

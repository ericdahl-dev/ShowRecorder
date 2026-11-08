@testable import Recording
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

/// What `resolveEnvironment()` keeps across several StoreKit answers in one launch (#994). Each test feeds its own
/// `Resolved`, so no static state is shared between tests.
@Suite("Demo signal availability: answers in one launch")
struct DemoSignalResolvedTests {
    private func kept(after answers: [DistributionEnvironment]) -> (kept: DistributionEnvironment?, returned: [DistributionEnvironment]) {
        let resolved = DemoSignalAvailability.Resolved()
        let returned = answers.map { resolved.remember($0) }
        return (resolved.environment, returned)
    }

    @Test("Nothing is kept before the first answer")
    func noAnswerYet() {
        #expect(DemoSignalAvailability.Resolved().environment == nil)
    }

    @Test("A failed answer after TestFlight keeps TestFlight, so the Demo signal stays offered")
    func sandboxThenUnknown() {
        let result = kept(after: [.sandbox, .unknown])
        #expect(result.kept == .sandbox)
        #expect(result.returned == [.sandbox, .sandbox])
        #expect(DemoSignalAvailability.isAvailable(isDebugBuild: false, environment: result.kept))
    }

    @Test("A failed answer after the App Store keeps the App Store")
    func productionThenUnknown() {
        let result = kept(after: [.production, .unknown, .unknown])
        #expect(result.kept == .production)
        #expect(result.returned == [.production, .production, .production])
    }

    @Test("A launch that starts offline picks up TestFlight once StoreKit answers")
    func unknownThenSandbox() {
        let result = kept(after: [.unknown, .sandbox])
        #expect(result.kept == .sandbox)
        #expect(result.returned == [.unknown, .sandbox])
        #expect(DemoSignalAvailability.isAvailable(isDebugBuild: false, environment: result.kept))
    }

    @Test("Only failed answers keep unknown")
    func onlyUnknown() {
        let result = kept(after: [.unknown, .unknown])
        #expect(result.kept == .unknown)
        #expect(!DemoSignalAvailability.isAvailable(isDebugBuild: false, environment: result.kept))
    }

    @Test("Two verified answers that differ keep the newer one")
    func verifiedThenOtherVerified() {
        #expect(kept(after: [.sandbox, .production]).kept == .production)
        #expect(kept(after: [.production, .sandbox]).kept == .sandbox)
    }
}

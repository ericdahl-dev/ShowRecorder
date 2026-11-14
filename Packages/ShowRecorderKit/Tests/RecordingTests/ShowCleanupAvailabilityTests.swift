@testable import Recording
import Testing

/// Selecting several Shows and deleting them at once (#1217) is offered in every build, App Store included (Eric,
/// 2026-11-14), after he tried it on an iPhone from TestFlight build 1.2.13 (64.1).
@Suite("Show clean-up availability")
struct ShowCleanupAvailabilityTests {
    @Test("Offered everywhere: Debug, TestFlight, the App Store, and before StoreKit has answered")
    func everyone() {
        #expect(ShowCleanupAvailability.isAvailable(isDebugBuild: true, environment: nil))
        #expect(ShowCleanupAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
        #expect(ShowCleanupAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(ShowCleanupAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(ShowCleanupAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }
}

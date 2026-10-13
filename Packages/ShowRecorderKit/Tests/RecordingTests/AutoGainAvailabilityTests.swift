@testable import Recording
import Testing

/// Auto-gain stays out of TestFlight and the App Store until it has run on a real desk with real audio (Eric,
/// 2026-10-12, v1.1.1): Debug builds only.
@Suite("Auto-gain availability")
struct AutoGainAvailabilityTests {
    @Test("Offered in a Debug build only, whatever the distribution")
    func debugOnly() {
        #expect(AutoGainAvailability.isAvailable(isDebugBuild: true))
        #expect(!AutoGainAvailability.isAvailable(isDebugBuild: false))
    }
}

import MixerLink
@testable import Recording
import Testing

/// Mixer Link for the Behringer WING (#417) is offered in Debug and TestFlight builds, so a tester with a real WING can
/// try it (Eric, 2026-11-10); not in the App Store build.
@Suite("WING availability")
struct WingAvailabilityTests {
    @Test("Debug builds offer it, whatever the environment")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(WingAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("A TestFlight build offers it, so a tester with a real WING can try it (Eric, 2026-11-10)")
    func testFlightBuild() {
        #expect(WingAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store build, or an unknown or unanswered environment, does not")
    func notOffered() {
        for environment: DistributionEnvironment? in [nil, .unknown, .production] {
            #expect(!WingAvailability.isAvailable(isDebugBuild: false, environment: environment))
        }
    }

    @Test("The families Mixer Link offers: the WING joins the X Air and the X32 only where it is available")
    func families() {
        #expect(WingAvailability.families(isDebugBuild: true) == [.xAir, .x32, .wing])
        #expect(WingAvailability.families(isDebugBuild: false) == [.xAir, .x32])
    }
}

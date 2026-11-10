import MixerLink
@testable import Recording
import Testing

/// Mixer Link for the Behringer WING (#417) is offered in Debug builds only until Eric has tried it on a real WING.
@Suite("WING availability")
struct WingAvailabilityTests {
    @Test("Debug builds offer it, whatever the environment")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(WingAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight and App Store builds do not")
    func releaseBuilds() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(!WingAvailability.isAvailable(isDebugBuild: false, environment: environment))
        }
    }

    @Test("The families Mixer Link offers: the WING joins the X Air and the X32 only where it is available")
    func families() {
        #expect(WingAvailability.families(isDebugBuild: true) == [.xAir, .x32, .wing])
        #expect(WingAvailability.families(isDebugBuild: false) == [.xAir, .x32])
    }
}

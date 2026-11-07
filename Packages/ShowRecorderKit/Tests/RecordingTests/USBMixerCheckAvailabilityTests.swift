@testable import Recording
import Testing

/// Checking that the linked Mixer is the one plugged in by USB (#1018) is offered in Debug and TestFlight builds, never
/// the App Store build (Eric, 2026-11-07). Opening it up is this one rule.
@Suite("USB Mixer check availability")
struct USBMixerCheckAvailabilityTests {
    @Test("It is at the Debug + TestFlight level (#1018)")
    func level() {
        #expect(USBMixerCheckAvailability.level == .debugAndTestFlight)
    }

    @Test("Debug builds offer it whatever the environment, even before it is known")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(USBMixerCheckAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("TestFlight (sandbox) builds offer it")
    func testFlightBuild() {
        #expect(USBMixerCheckAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store (production) build doesn't, nor a Release build whose environment is unknown or not yet answered")
    func appStoreBuild() {
        #expect(!USBMixerCheckAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(!USBMixerCheckAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(!USBMixerCheckAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }
}

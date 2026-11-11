import Recording
import Testing

/// In Debug builds the Demo signal offers Mixer Link, as an X Air (18 channels) or an X32 (32), so the Mixer Link test
/// bench (tools/mixer-sim) can be tried from a phone with no mixer plugged in (#417, Eric 2026-11-11). Which family each
/// Demo signal is comes from `MixerFamily.ready(interfaceName:demoChannelCount:demoCounts:)`, tested with
/// `DemoMixerFamilyAvailability`.
@Suite("Demo signal Mixer Link availability")
struct DemoMixerLinkAvailabilityTests {
    @Test("Debug builds offer it whatever the environment; no Release build does, not even TestFlight")
    func debugOnly() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(DemoMixerLinkAvailability.isAvailable(isDebugBuild: true, environment: environment))
            #expect(!DemoMixerLinkAvailability.isAvailable(isDebugBuild: false, environment: environment))
        }
    }
}

@Suite("Demo signal Mixer Link in this build")
struct DemoMixerLinkAvailabilityThisBuildTests {
    @Test("A Debug build offers it; a Release build never does")
    func thisBuild() {
        #if DEBUG
        #expect(DemoMixerLinkAvailability.isAvailableInThisBuild)
        #else
        #expect(!DemoMixerLinkAvailability.isAvailableInThisBuild)
        #endif
    }
}

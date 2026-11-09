import MixerLink
import Recording
import Testing

/// The Demo signal counts as an X Air for packs and the license in review and TestFlight builds, so App Review, which
/// has no X Air, can reach the X Air pack (#705); the 32-channel Demo signal counts as an X32 the same way (Eric,
/// 2026-11-09).
@Suite("Demo mixer family availability")
struct DemoMixerFamilyAvailabilityTests {
    @Test("Debug builds count the Demo signal as an X Air whatever the environment (#705)")
    func debugBuild() {
        for environment: DistributionEnvironment? in [nil, .unknown, .sandbox, .production] {
            #expect(DemoMixerFamilyAvailability.isAvailable(isDebugBuild: true, environment: environment))
        }
    }

    @Test("A sandbox build (TestFlight, App Review) counts it (#705)")
    func sandboxBuild() {
        #expect(DemoMixerFamilyAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
    }

    @Test("The App Store build, or an unknown or unanswered environment, does not (#705)")
    func notCounted() {
        #expect(!DemoMixerFamilyAvailability.isAvailable(isDebugBuild: false, environment: .production))
        #expect(!DemoMixerFamilyAvailability.isAvailable(isDebugBuild: false, environment: .unknown))
        #expect(!DemoMixerFamilyAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }

    @Test("The 18-channel Demo signal is an X Air where the rule allows, no family otherwise, never an X32 (#705)")
    func demoFamily() {
        #expect(MixerFamily.ready(interfaceName: "Demo signal", demoChannelCount: 18, demoCounts: true) == .xAir)
        #expect(MixerFamily.ready(interfaceName: "Demo signal", demoChannelCount: 18, demoCounts: false) == nil)
        for demoCounts in [true, false] {
            #expect(MixerFamily.ready(interfaceName: "Demo signal", demoChannelCount: 18, demoCounts: demoCounts) != .x32)
        }
    }

    @Test("The 32-channel Demo signal is an X32 where the rule allows, no family otherwise (Eric, 2026-11-09)")
    func demo32Family() {
        #expect(MixerFamily.ready(interfaceName: "Demo signal", demoChannelCount: 32, demoCounts: true) == .x32)
        #expect(MixerFamily.ready(interfaceName: "Demo signal", demoChannelCount: 32, demoCounts: false) == nil)
    }

    @Test("A real interface keeps its own family whatever the rule says (#705)")
    func realInterface() {
        for demoCounts in [true, false] {
            #expect(MixerFamily.ready(interfaceName: "X18/XR18", demoChannelCount: nil, demoCounts: demoCounts) == .xAir)
            #expect(MixerFamily.ready(interfaceName: "EVO 4", demoChannelCount: nil, demoCounts: demoCounts) == nil)
            #expect(MixerFamily.ready(interfaceName: "Demo signal", demoChannelCount: nil, demoCounts: demoCounts) == nil)
        }
    }
}

@Suite("Demo as an X Air in this build")
struct DemoMixerFamilyAvailabilityThisBuildTests {
    @Test("A Debug build counts the Demo signal before the environment is known; a Release build waits for a sandbox answer (#705)")
    func thisBuild() {
        #if DEBUG
        #expect(DemoMixerFamilyAvailability.isAvailableInThisBuild)
        #else
        #expect(!DemoMixerFamilyAvailability.isAvailableInThisBuild, "no environment resolved in tests")
        #endif
    }
}

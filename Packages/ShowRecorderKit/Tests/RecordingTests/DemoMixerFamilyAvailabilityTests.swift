import MixerLink
import Recording
import Testing

/// The Demo signal counts as an X Air for packs and the license in review and TestFlight builds, so App Review, which
/// has no X Air, can reach the X Air pack (#705).
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

    @Test("The Demo signal is an X Air where the rule allows, no family otherwise, never an X32 (#705)")
    func demoFamily() {
        #expect(MixerFamily.armed(interfaceName: "Demo signal", isDemo: true, demoCounts: true) == .xAir)
        #expect(MixerFamily.armed(interfaceName: "Demo signal", isDemo: true, demoCounts: false) == nil)
        for demoCounts in [true, false] {
            #expect(MixerFamily.armed(interfaceName: "Demo signal", isDemo: true, demoCounts: demoCounts) != .x32)
        }
    }

    @Test("A real interface keeps its own family whatever the rule says (#705)")
    func realInterface() {
        for demoCounts in [true, false] {
            #expect(MixerFamily.armed(interfaceName: "X18/XR18", isDemo: false, demoCounts: demoCounts) == .xAir)
            #expect(MixerFamily.armed(interfaceName: "EVO 4", isDemo: false, demoCounts: demoCounts) == nil)
            #expect(MixerFamily.armed(interfaceName: "Demo signal", isDemo: false, demoCounts: demoCounts) == nil)
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

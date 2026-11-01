import MixerLink

/// Where the Demo signal counts as an X Air for mixer packs and the license (#705): Debug builds, and sandbox builds,
/// so App Review, which has no X Air, can reach the X Air pack. The App Store build's customers never get it.
///
/// StoreKit's `AppTransaction` environment is sandbox for TestFlight, and is expected to be sandbox for a build under App
/// Review too (App Review's purchases run in the sandbox, which is why receipt validation falls back to it); it is
/// production for customers. If App Review turned out to be production, it would see neither the Demo signal nor the
/// pack: nothing reaches customers either way. So
/// the same rule as `DemoSignalAvailability` covers App Review and TestFlight, and in production the Demo signal isn't
/// even offered. Only the pack offer and the license read this; Mixer Link, channel naming and the rest still see no
/// mixer family on the Demo signal.
public enum DemoMixerFamilyAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from the environment `DemoSignalAvailability.resolveEnvironment()` has found.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

extension MixerFamily {
    /// The Ready input's family for packs and the license (#705): an X Air for the Demo signal where
    /// `DemoMixerFamilyAvailability` allows it (`demoCounts`), none for it otherwise; any other input's family from its
    /// interface name.
    public static func ready(interfaceName: String, isDemo: Bool, demoCounts: Bool) -> MixerFamily? {
        if isDemo { return demoCounts ? .xAir : nil }
        return MixerFamily(audioInterfaceName: interfaceName)
    }
}

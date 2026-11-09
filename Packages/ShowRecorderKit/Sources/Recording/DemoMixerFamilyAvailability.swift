import MixerLink

/// Where the Demo signal counts as a mixer for mixer packs and the license (#705): the 18-channel Demo signal as an X Air,
/// the 32-channel one as an X32 (Eric, 2026-11-09). Debug builds, and sandbox builds, so App Review, which has no X Air
/// or X32, can reach those packs. The App Store build's customers never get it.
///
/// StoreKit's `AppTransaction` environment is sandbox for TestFlight, and is expected to be sandbox for a build under App
/// Review too (App Review's purchases run in the sandbox, which is why receipt validation falls back to it); it is
/// production for customers. If App Review turned out to be production, it would see neither the Demo signal nor the
/// pack: nothing reaches customers either way. So
/// the same rule as `DemoSignalAvailability` covers App Review and TestFlight, and in production the Demo signal isn't
/// even offered. Only the pack offer and the license read this; Mixer Link, channel naming and the rest still see no
/// mixer family on either Demo signal.
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
    /// The Ready input's family for packs and the license (#705). For a Demo signal (`demoChannelCount` is its channel
    /// count, nil for any other input) where `DemoMixerFamilyAvailability` allows it (`demoCounts`): an X32 for the
    /// 32-channel one, an X Air for the 18-channel one; none otherwise. Any other input's family comes from its
    /// interface name.
    public static func ready(interfaceName: String, demoChannelCount: Int?, demoCounts: Bool) -> MixerFamily? {
        if let demoChannelCount {
            guard demoCounts else { return nil }
            return demoChannelCount >= 32 ? .x32 : .xAir
        }
        return MixerFamily(audioInterfaceName: interfaceName)
    }
}

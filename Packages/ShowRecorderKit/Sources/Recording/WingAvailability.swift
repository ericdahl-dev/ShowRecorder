import MixerLink

/// Where Mixer Link for the Behringer WING (#417) is offered: Debug builds only, until Eric has tried it on a real WING.
/// The driver is built from Maillot's WING Remote Protocols document alone, with no WING or emulator yet. The app turns
/// the family on at launch (`MixerFamily.offersWing`), so other builds never ask for a WING on the network.
public enum WingAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugOnly

    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }

    /// The mixer families Mixer Link offers in a build of this kind.
    public static func families(isDebugBuild: Bool) -> [MixerFamily] {
        MixerFamily.offered(wing: isAvailable(isDebugBuild: isDebugBuild, environment: nil))
    }
}

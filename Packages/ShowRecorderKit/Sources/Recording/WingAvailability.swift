import MixerLink

/// Where Mixer Link for the Behringer WING (#417) is offered: Debug and TestFlight builds, so a tester with a real WING
/// can try it (Eric, 2026-11-10); not the App Store build. The driver is built from Maillot's WING Remote Protocols
/// document and checked against fakes and wingemul, never yet a real WING. The app turns
/// the family on at launch (`MixerFamily.offersWing`), so other builds never ask for a WING on the network.
public enum WingAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

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

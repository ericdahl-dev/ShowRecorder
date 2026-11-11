/// Where the Demo signal offers Mixer Link (#417, Eric 2026-11-11): the 18-channel Demo signal as an X Air, the 32-channel
/// one as an X32, as `MixerFamily.ready(interfaceName:demoChannelCount:demoCounts:)` says. It lets the Mixer Link test bench
/// (tools/mixer-sim) be tried from a phone with no mixer plugged in. Debug builds only: a tester's Demo signal never
/// links to a real mixer. The WING has no Demo signal, so it still needs its own interface.
public enum DemoMixerLinkAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugOnly

    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

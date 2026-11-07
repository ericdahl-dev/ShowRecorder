/// Where the Mixer session checks that the linked Mixer is the one plugged in by USB (#1018): after each new Link it asks
/// the network for other Mixers of the linked one's family, and with more than one, auto-gain and clip protection wait
/// until the operator picks the USB one in Find Mixers. Debug and TestFlight builds only (Eric, 2026-11-07): two Mixers
/// of one family on a network is rare, so the App Store build keeps the Link as before, with no scan and no pick.
/// Opening it up is this one rule. The app hands it to `MixerSession(checksUSBMixer:)`.
public enum USBMixerCheckAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer offers it in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

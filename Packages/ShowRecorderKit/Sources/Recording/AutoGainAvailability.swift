/// Where auto-gain (#155) is offered: every build, the App Store included (Eric, 2026-10-29), after his live XR18 test
/// (2026-10-14). It is still Pro (`needsPro`).
public enum AutoGainAvailability {
    /// Where it is offered; moving it is this one line.
    public static let level: AvailabilityLevel = .everyone

    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }
}

/// Where auto-gain may move an X32 or M32's preamps: Debug and TestFlight builds, as auto-gain has been tested live only
/// on an XR18 (#494). Elsewhere an X32's sheet says `.cantSetGain`. Its own rule, so it can move on its own.
public enum X32AutoGainAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }
}

extension AutoGainAvailability {
    /// Why auto-gain can't run right now, said on its sheet instead of hiding it (#155).
    public enum Unavailable: Equatable, Sendable {
        /// Moving a preamp mid-Take would make the recorded level jump.
        case takeRunning
        /// Mixer Link is still connecting.
        case connecting
        /// No Mixer to move the preamps on.
        case noMixerLink
        /// The Link is on another Mixer than the Ready one (#647): "FOH (XR18)".
        case otherMixerLinked(String)
        /// The linked Mixer's preamps can't be set from ShowRecorder.
        case cantSetGain
        /// Auto-gain is Pro, and this is Free (#705).
        case needsPro

        public var message: String {
            switch self {
            case .takeRunning:
                "Not during a Take: moving a preamp would make the recorded level jump. Stop the Take first."
            case .connecting:
                "Connecting to the Mixer. Auto-gain is ready once Mixer Link is up."
            case .noMixerLink:
                "Auto-gain moves the preamps on the Mixer. Connect to it in Settings › Mixer Link first."
            case .otherMixerLinked(let which):
                "The Mixer Link is on \(which), not the Mixer you're recording from. Connect to that Mixer in Settings › Mixer Link first."
            case .cantSetGain:
                "ShowRecorder can't set this Mixer's preamp gain yet."
            case .needsPro:
                "Auto-gain is part of Pro. Get it in Settings › Pro."
            }
        }
    }

    /// Nil when auto-gain can run; otherwise the reason, a running Take first, then Pro.
    /// - Parameter allowed: whether the plan now includes auto-gain (`License.allowsAutoGain`).
    public static func whyNot(hasMixerLink: Bool, isConnecting: Bool = false, canSetGain: Bool, isRecording: Bool,
                              otherMixer: String? = nil, allowed: Bool = true) -> Unavailable? {
        if isRecording { return .takeRunning }
        if !allowed { return .needsPro }
        if !hasMixerLink {
            if let otherMixer { return .otherMixerLinked(otherMixer) }
            return isConnecting ? .connecting : .noMixerLink
        }
        if !canSetGain { return .cantSetGain }
        return nil
    }
}

/// The subject and body of the support email Settings opens (#722). Every fact is one line the user can read, edit or
/// delete before sending; the app sends nothing itself. Only fixed facts about the app, the device and the audio
/// setup go in (an input's name only when it is a USB interface's): no recordings, Show or file names, paths, UIDs or other identifiers.
public struct SupportDiagnostics: Equatable, Sendable {
    /// How this build reached the device.
    public enum Distribution: String, Sendable, Equatable {
        case debug = "Debug"
        case testFlight = "TestFlight"
        case appStore = "App Store"
        case unknown = "Unknown"

        public init(isDebugBuild: Bool, environment: DistributionEnvironment?) {
            if isDebugBuild { self = .debug; return }
            switch environment {
            case .sandbox: self = .testFlight
            case .production: self = .appStore
            case .unknown, nil: self = .unknown
            }
        }
    }

    /// `CFBundleShortVersionString` and `CFBundleVersion`; nil when the bundle doesn't say.
    public var version: String?
    public var build: String?
    public var distribution: Distribution
    /// The hardware model, such as "iPhone16,1" or "Mac15,3".
    public var device: String
    /// The OS and its version, such as "iOS 26.0.1".
    public var system: String
    /// The current audio input route, from `routeLabel`; nil when no input is Armed.
    public var inputRoute: String?
    public var channelCount: Int?
    public var sampleRate: Int?
    /// Whether a Drive folder is chosen. Never which one.
    public var driveFolderSet: Bool
    /// Why the system last interrupted audio since launch, if it has.
    public var lastInterruption: InterruptionPolicy.Reason?
    /// The Mixer Link's family and Mixer, or nil when it isn't linked.
    public var mixerLink: String?

    public init(
        version: String?, build: String?, distribution: Distribution, device: String, system: String,
        inputRoute: String?, channelCount: Int?, sampleRate: Int?, driveFolderSet: Bool,
        lastInterruption: InterruptionPolicy.Reason?, mixerLink: String?
    ) {
        self.version = version
        self.build = build
        self.distribution = distribution
        self.device = device
        self.system = system
        self.inputRoute = inputRoute
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.driveFolderSet = driveFolderSet
        self.lastInterruption = lastInterruption
        self.mixerLink = mixerLink
    }

    /// "ShowRecorder support (v1.1.6 (34.1))": the version, then the build.
    public var subject: String {
        "ShowRecorder support (v\(version ?? "?") (\(build ?? "?")))"
    }

    /// Blank lines to write in, then the titled block.
    public var body: String {
        let rule = String(repeating: "-", count: 40)
        let channels: String
        if channelCount == nil && sampleRate == nil {
            channels = "Not armed"
        } else {
            let count = channelCount.flatMap { $0 > 0 ? "\($0)" : nil } ?? "unknown"
            channels = "\(count) at \(sampleRate.map { "\($0) Hz" } ?? "unknown rate")"
        }
        return """


        \(rule)
        Diagnostics (you can delete these)
        \(rule)
        App: \(version ?? "?") (build \(build ?? "?"))
        Distribution: \(distribution.rawValue)
        Device: \(device)
        System: \(system)
        Audio input: \(inputRoute ?? "None")
        Channels: \(channels)
        Drive folder set: \(driveFolderSet ? "yes" : "no")
        Last interruption: \(lastInterruption.map(Self.line) ?? "None")
        Mixer Link: \(mixerLink ?? "Not linked")
        """
    }

    /// `USB Audio "X32"`: the port type in words, then the port's name in quotes. The name is printed only for a USB
    /// port (an interface's product name) or where the platform has no port type and the caller vouches for it: a
    /// Bluetooth or renamed device can be named after its owner. `portType` is `AVAudioSession.Port.rawValue`.
    public static func routeLabel(portType: String?, name: String?) -> String {
        let words: String = switch portType {
        case "USBAudio": "USB Audio"
        case "MicrophoneBuiltIn": "Built-in microphone"
        case "MicrophoneWired", "HeadsetMic": "Headset microphone"
        case "BluetoothHFP", "BluetoothA2DP", "BluetoothLE": "Bluetooth"
        case "LineIn": "Line in"
        case nil: "Audio interface"
        case let other?: other
        }
        guard let name, portType == nil || portType == "USBAudio" else { return words }
        return "\(words) \"\(name)\""
    }

    private static func line(_ reason: InterruptionPolicy.Reason) -> String {
        switch reason {
        case .other: "a call, Siri or another app"
        case .builtInMicMuted: "built-in microphone muted"
        case .routeDisconnected: "input disconnected"
        }
    }
}

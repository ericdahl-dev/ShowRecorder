import Recording
import Telemetry
import TelemetrySinks

/// The app's one `Telemetry` (ADR 0007, #1026): crashes and handled failures to GlitchTip, usage to PostHog, only
/// while Settings › Share crash reports and usage is on and `TelemetryAvailability` offers it (Debug + TestFlight).
/// Never called from the real-time audio path (ADR 0002).
@MainActor
enum AppTelemetry {
    /// Silent until `launch()`: sends nothing before StoreKit has said whether this is TestFlight.
    private(set) static var shared = Telemetry(sinks: [], isAvailable: { false })
    private static var launched = false
    /// The latest plan, kept so the hub made at launch starts with it.
    private static var tier: TelemetryTier?

    /// The plan as owned (`ProStore.planLicense().tier`): on every usage event and as a tag on crashes and failures
    /// (ADR 0007). Nil until the App Store has answered.
    static func setTier(_ tier: Tier?) {
        let sent: TelemetryTier? = switch tier {
        case .free: .free
        case .trial: .trial
        case .pro: .pro
        case nil: nil
        }
        self.tier = sent
        shared.setTier(sent)
    }

    /// Once per run, from the main window: learns the distribution environment, starts the sinks and sends
    /// app_opened. A crash before this point isn't reported; StoreKit usually answers within a second.
    static func launch() async {
        guard !launched else { return }
        launched = true
        let environment = await DemoSignalAvailability.resolveEnvironment()
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        let name = TelemetryEnvironment.name(isDebugBuild: isDebugBuild, isTestFlight: environment == .sandbox)
        shared = Telemetry(
            sinks: [SentrySink(environment: name), PostHogSink()],
            isAvailable: { TelemetryAvailability.isAvailableInThisBuild }
        )
        shared.start()
        shared.setTier(tier)
        shared.send(.appOpened)
    }
}

import Foundation
import PostHog
import Sentry
import Synchronization
import Telemetry

/// What `SentrySink` asks of the Sentry SDK. The real calls are `SentrySDKClient` in SDKAdapters.swift; tests use a
/// fake, so they send nothing.
@MainActor
protocol ErrorReportingClient: AnyObject {
    func start(environment: String)
    func setUser(id: String)
    func close()
    func addBreadcrumb(category: String, message: String)
    func captureMessage(_ message: String, tags: [String: String])
}

/// What `PostHogSink` asks of the PostHog SDK. The real calls are `PostHogSDKClient` in SDKAdapters.swift.
@MainActor
protocol AnalyticsClient: AnyObject {
    /// Sets the SDK up, with `filter` as its `beforeSend`: every event, ours and the SDK's own, passes through it.
    func setup(filter: PostHogEventFilter)
    func optIn()
    func optOut()
    func capture(_ event: String, distinctId: String, properties: [String: Any])
}

/// Crashes and handled failures to GlitchTip (errors.ericdahl.dev, project showrecorder), through the Sentry SDK
/// (ADR 0007). Only crashes and errors: no PII, no tracing, no app-hang tracking, no automatic breadcrumbs, no network
/// tracking. The install ID is the user ID, so one install's crashes group together.
@MainActor
public final class SentrySink: TelemetrySink {
    /// GlitchTip's public key for project showrecorder (12): it can only send events.
    nonisolated static let dsn = "https://046141a3ff134035b0781c4ed1ca75b1@errors.ericdahl.dev/12"

    private let environment: String
    private let client: any ErrorReportingClient

    /// `environment` is `TelemetryEnvironment.name(...)`: debug, testflight or appstore.
    public convenience init(environment: String) {
        self.init(environment: environment, client: SentrySDKClient())
    }

    init(environment: String, client: any ErrorReportingClient) {
        self.environment = environment
        self.client = client
    }

    nonisolated static func configure(_ options: Options, environment: String) {
        options.dsn = dsn
        options.environment = environment
        options.sendDefaultPii = false
        options.tracesSampleRate = 0
        options.enableAppHangTracking = false
        options.enableAutoBreadcrumbTracking = false
        options.enableNetworkTracking = false
        options.enableCaptureFailedRequests = false
    }

    public func start(installID: UUID) {
        client.start(environment: environment)
        client.setUser(id: installID.uuidString)
    }

    public func stop() {
        client.close()
    }

    /// Usage events become breadcrumbs, so a crash shows what the app was doing just before.
    public func capture(_ event: TelemetryEvent) {
        client.addBreadcrumb(category: "usage", message: event.name)
    }

    public func setTier(_ tier: TelemetryTier?) {}

    public func capture(_ failure: TelemetryFailure) {
        client.captureMessage(failure.summary, tags: [
            "area": failure.area.rawValue,
            "error_type": failure.errorType,
            "error_domain": failure.domain,
            "error_code": String(failure.code),
        ])
    }
}

/// Usage to PostHog, project Owned Sites (beside showrecorder.app's visits), tagged `app: showrecorder` (ADR 0007).
/// Each event is sent with the install ID as its distinct ID; no person profiles, no feature flags, no session replay.
/// The one automatic event is the SDK's rage-click (`$rageclick`), which `PostHogEventFilter` keys by the install ID.
@MainActor
public final class PostHogSink: TelemetrySink {
    /// Owned Sites' public project key, the same one showrecorder.app uses: it can only send events.
    nonisolated static let projectToken = "phc_uzsUUTbN2k3EJVDvtTGBtrRgPmdWrRxzxbLZcsw7Vvm4"
    nonisolated static let host = "https://us.i.posthog.com"

    private let client: any AnalyticsClient
    private let filter: PostHogEventFilter
    private var installID: String?
    private var isSetUp = false
    private var tier: TelemetryTier?

    public convenience init() {
        self.init(client: PostHogSDKClient())
    }

    /// `defaults` holds the app's settings, where the rage-click filter reads the transport side.
    init(client: any AnalyticsClient, defaults: UserDefaults = .standard) {
        self.client = client
        filter = PostHogEventFilter(defaults: defaults)
    }

    nonisolated static func configure(_ config: PostHogConfig) {
        config.personProfiles = .never
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        // Rage-clicks are in ADR 0007's fixed list. Set here rather than left to the SDK's default, so a new SDK
        // version can't drop them or change what turns them on unseen. The SDK detects them on iOS only.
        #if os(iOS) || targetEnvironment(macCatalyst)
        config.rageClickConfig.enabled = true
        #endif
    }

    nonisolated static func properties(for event: TelemetryEvent) -> [String: Any] {
        var properties: [String: Any] = ["app": "showrecorder"]
        for (key, value) in event.properties {
            switch value {
            case let .int(number): properties[key] = number
            case let .string(text): properties[key] = text
            case let .bool(flag): properties[key] = flag
            }
        }
        return properties
    }

    public func start(installID: UUID) {
        self.installID = installID.uuidString
        filter.setInstallID(installID.uuidString)
        if isSetUp {
            client.optIn()
        } else {
            client.setup(filter: filter)
            isSetUp = true
        }
    }

    public func stop() {
        client.optOut()
        installID = nil
        filter.setInstallID(nil)
    }

    public func capture(_ event: TelemetryEvent) {
        switch event {
        case .takeStarted: filter.setTakeRunning(true)
        case .takeStopped: filter.setTakeRunning(false)
        default: break
        }
        guard let installID else { return }
        var properties = Self.properties(for: event)
        if let tier { properties["tier"] = tier.rawValue }
        client.capture(event.name, distinctId: installID, properties: properties)
    }

    /// Handled failures go to GlitchTip only.
    public func capture(_ failure: TelemetryFailure) {}

    /// Every event after this says the plan (ADR 0007).
    public func setTier(_ tier: TelemetryTier?) {
        self.tier = tier
    }
}

/// An event on its way out of the PostHog SDK: what `beforeSend` may change.
struct PostHogOutgoingEvent {
    var name: String
    var distinctId: String
    var properties: [String: Any]
}

/// The PostHog SDK's `beforeSend` (ADR 0007). Our own events already carry the install ID and pass as they are. The
/// SDK's rage-click is keyed by its own anonymous ID, so it gets the install ID instead, and it is dropped while
/// there is none (the switch is off). Person profiles stay off: this changes only the event's distinct ID.
/// A rage-click also says which side the landscape transport column is on and whether a Take is running, and loses
/// what the ADR doesn't name: the tapped elements (which can hold text) and the screen name. The tap position and
/// the context every event carries (screen size, device, system, app version) stay.
/// The SDK calls it from whatever thread captured the event, so the state sits behind a lock.
final class PostHogEventFilter: Sendable {
    static let rageClick = "$rageclick"
    /// `RecordScreenModel.transportLeadingKey` in the app: true when the record button is on the left in landscape.
    static let transportLeadingKey = "transportLeading"
    /// What the SDK adds to a rage-click that ADR 0007 doesn't name.
    static let droppedRageClickProperties = ["$elements_chain", "$event_type", "$screen_name"]

    private struct State {
        var installID: String?
        var takeRunning = false
    }

    private let state = Mutex(State())
    /// UserDefaults is thread-safe (Apple's documentation), though Foundation doesn't mark it `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func setInstallID(_ id: String?) {
        state.withLock { $0.installID = id }
    }

    func setTakeRunning(_ running: Bool) {
        state.withLock { $0.takeRunning = running }
    }

    /// The event to send, or nil to drop it.
    func filter(_ event: PostHogOutgoingEvent) -> PostHogOutgoingEvent? {
        guard event.name == Self.rageClick else { return event }
        let (installID, takeRunning) = state.withLock { ($0.installID, $0.takeRunning) }
        guard let installID else { return nil }
        var event = event
        event.distinctId = installID
        for key in Self.droppedRageClickProperties { event.properties.removeValue(forKey: key) }
        event.properties["transport_leading"] = defaults.bool(forKey: Self.transportLeadingKey)
        event.properties["take_running"] = takeRunning
        return event
    }
}

/// The environment name both sinks tag their events with.
public enum TelemetryEnvironment {
    public static func name(isDebugBuild: Bool, isTestFlight: Bool) -> String {
        if isDebugBuild { return "debug" }
        return isTestFlight ? "testflight" : "appstore"
    }
}

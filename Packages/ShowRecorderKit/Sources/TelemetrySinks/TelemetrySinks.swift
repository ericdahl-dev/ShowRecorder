import Foundation
import PostHog
import Sentry
import Telemetry

/// Crashes and handled failures to GlitchTip (errors.ericdahl.dev, project showrecorder), through the Sentry SDK
/// (ADR 0007). Only crashes and errors: no PII, no tracing, no app-hang tracking, no automatic breadcrumbs, no network
/// tracking. The install ID is the user ID, so one install's crashes group together.
@MainActor
public final class SentrySink: TelemetrySink {
    /// GlitchTip's public key for project showrecorder (12): it can only send events.
    nonisolated static let dsn = "https://046141a3ff134035b0781c4ed1ca75b1@errors.ericdahl.dev/12"

    private let environment: String

    /// `environment` is `TelemetryEnvironment.name(...)`: debug, testflight or appstore.
    public init(environment: String) {
        self.environment = environment
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
        let environment = environment
        SentrySDK.start { options in Self.configure(options, environment: environment) }
        SentrySDK.setUser(User(userId: installID.uuidString))
    }

    public func stop() {
        SentrySDK.close()
    }

    /// Usage events become breadcrumbs, so a crash shows what the app was doing just before.
    public func capture(_ event: TelemetryEvent) {
        let crumb = Breadcrumb(level: .info, category: "usage")
        crumb.message = event.name
        SentrySDK.addBreadcrumb(crumb)
    }

    public func capture(_ failure: TelemetryFailure) {
        SentrySDK.capture(message: failure.summary) { scope in
            scope.setTag(value: failure.area.rawValue, key: "area")
            scope.setTag(value: failure.errorType, key: "error_type")
            scope.setTag(value: failure.domain, key: "error_domain")
            scope.setTag(value: String(failure.code), key: "error_code")
        }
    }
}

/// Usage to PostHog, project Owned Sites (beside showrecorder.app's visits), tagged `app: showrecorder` (ADR 0007).
/// Each event is sent with the install ID as its distinct ID; no person profiles, no automatic events, no feature
/// flags, no session replay.
@MainActor
public final class PostHogSink: TelemetrySink {
    /// Owned Sites' public project key, the same one showrecorder.app uses: it can only send events.
    nonisolated static let projectToken = "phc_uzsUUTbN2k3EJVDvtTGBtrRgPmdWrRxzxbLZcsw7Vvm4"
    nonisolated static let host = "https://us.i.posthog.com"

    private var installID: String?
    private var isSetUp = false

    public init() {}

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
        if isSetUp {
            PostHogSDK.shared.optIn()
            return
        }
        let config = PostHogConfig(projectToken: Self.projectToken, host: Self.host)
        config.personProfiles = .never
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        PostHogSDK.shared.setup(config)
        isSetUp = true
    }

    public func stop() {
        PostHogSDK.shared.optOut()
        installID = nil
    }

    public func capture(_ event: TelemetryEvent) {
        guard let installID else { return }
        PostHogSDK.shared.capture(event.name, distinctId: installID, properties: Self.properties(for: event))
    }

    /// Handled failures go to GlitchTip only.
    public func capture(_ failure: TelemetryFailure) {}
}

/// The environment name both sinks tag their events with.
public enum TelemetryEnvironment {
    public static func name(isDebugBuild: Bool, isTestFlight: Bool) -> String {
        if isDebugBuild { return "debug" }
        return isTestFlight ? "testflight" : "appstore"
    }
}

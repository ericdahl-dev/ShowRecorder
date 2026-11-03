import Foundation
import PostHog
import Sentry
import Telemetry
import Testing
@testable import TelemetrySinks

/// The app's sinks (ADR 0007, #1026): what the Sentry SDK is allowed to collect, what PostHog receives, and what each
/// sink asks of its SDK. The SDKs sit behind `ErrorReportingClient` and `AnalyticsClient`, so these tests use fakes
/// and send nothing; the real calls are the few lines in SDKAdapters.swift.
@Suite("Telemetry sinks")
struct TelemetrySinksTests {
    @Test("Sentry sends to the showrecorder GlitchTip project with everything beyond crashes and errors off")
    func sentryOptions() {
        let options = Options()
        SentrySink.configure(options, environment: "testflight")
        #expect(options.dsn == SentrySink.dsn)
        #expect(SentrySink.dsn.hasSuffix("@errors.ericdahl.dev/12"))
        #expect(options.environment == "testflight")
        #expect(options.sendDefaultPii == false)
        #expect(options.tracesSampleRate == 0)
        #expect(options.enableAppHangTracking == false)
        #expect(options.enableAutoBreadcrumbTracking == false)
        #expect(options.enableNetworkTracking == false)
        #expect(options.enableCaptureFailedRequests == false)
    }

    @Test("PostHog makes no person profiles, no automatic events and no feature flag calls")
    func postHogConfig() {
        let config = PostHogConfig(projectToken: PostHogSink.projectToken, host: PostHogSink.host)
        PostHogSink.configure(config)
        #expect(config.personProfiles == .never)
        #expect(config.captureApplicationLifecycleEvents == false)
        #expect(config.captureScreenViews == false)
        #expect(config.preloadFeatureFlags == false)
        #expect(config.sendFeatureFlagEvent == false)
    }

    @Test("PostHog gets the event's properties, tagged as the app")
    func postHogProperties() {
        let properties = PostHogSink.properties(
            for: .takeStopped(seconds: 90, channelCount: 18, dropouts: 1, cause: .operatorStop)
        )
        #expect(properties["app"] as? String == "showrecorder")
        #expect(properties["seconds"] as? Int == 90)
        #expect(properties["channel_count"] as? Int == 18)
        #expect(properties["dropouts"] as? Int == 1)
        #expect(properties["cause"] as? String == "operator")
        #expect(properties.count == 5)
    }

    @Test("An event with nothing to add carries only the app tag")
    func postHogAppTagOnly() {
        let properties = PostHogSink.properties(for: .appOpened)
        #expect(properties.count == 1)
        #expect(properties["app"] as? String == "showrecorder")
    }

    @Test("PostHog uses the Owned Sites project, beside showrecorder.app's visits")
    func postHogProject() {
        #expect(PostHogSink.projectToken == "phc_uzsUUTbN2k3EJVDvtTGBtrRgPmdWrRxzxbLZcsw7Vvm4")
        #expect(PostHogSink.host == "https://us.i.posthog.com")
    }

    @Test("The environment names Debug, TestFlight and App Store builds")
    func environments() {
        #expect(TelemetryEnvironment.name(isDebugBuild: true, isTestFlight: false) == "debug")
        #expect(TelemetryEnvironment.name(isDebugBuild: true, isTestFlight: true) == "debug")
        #expect(TelemetryEnvironment.name(isDebugBuild: false, isTestFlight: true) == "testflight")
        #expect(TelemetryEnvironment.name(isDebugBuild: false, isTestFlight: false) == "appstore")
    }
}

@MainActor
@Suite("Sentry sink")
struct SentrySinkTests {
    @Test("start() starts Sentry for the environment, with the install ID as the user")
    func start() {
        let client = FakeErrorReporting()
        let sink = SentrySink(environment: "debug", client: client)
        let id = UUID()
        sink.start(installID: id)
        #expect(client.calls == ["start debug", "user \(id.uuidString)"])
    }

    @Test("stop() closes Sentry")
    func stop() {
        let client = FakeErrorReporting()
        SentrySink(environment: "debug", client: client).stop()
        #expect(client.calls == ["close"])
    }

    @Test("A usage event becomes a breadcrumb, so a crash shows what came before")
    func breadcrumb() {
        let client = FakeErrorReporting()
        SentrySink(environment: "debug", client: client).capture(.takeStarted(channelCount: 18, destinations: .both, mixerFamily: nil))
        #expect(client.calls == ["breadcrumb usage take_started"])
    }

    @Test("A handled failure is sent with its area, error type, domain and code as tags")
    func failure() {
        let client = FakeErrorReporting()
        let failure = TelemetryFailure(area: .repair, error: NSError(domain: "TestDomain", code: 7))
        SentrySink(environment: "debug", client: client).capture(failure)
        #expect(client.calls == ["message \(failure.summary)"])
        #expect(client.tags == [
            "area": "repair", "error_type": failure.errorType, "error_domain": "TestDomain", "error_code": "7",
        ])
    }
}

@MainActor
@Suite("PostHog sink")
struct PostHogSinkTests {
    @Test("The first start() sets PostHog up once; events go out with the install ID as distinct ID")
    func firstStart() {
        let client = FakeAnalytics()
        let sink = PostHogSink(client: client)
        let id = UUID()
        sink.start(installID: id)
        sink.capture(.appOpened)
        #expect(client.calls == ["setup", "capture app_opened \(id.uuidString)"])
        #expect(client.lastProperties?["app"] as? String == "showrecorder")
    }

    @Test("stop() opts out and sends nothing more; start() again opts back in with the new ID, without a second setup")
    func stopAndRestart() {
        let client = FakeAnalytics()
        let sink = PostHogSink(client: client)
        sink.start(installID: UUID())
        sink.stop()
        sink.capture(.appOpened)
        let second = UUID()
        sink.start(installID: second)
        sink.capture(.showCreated)
        #expect(client.calls == ["setup", "optOut", "optIn", "capture show_created \(second.uuidString)"])
    }

    @Test("Nothing is sent before start()")
    func beforeStart() {
        let client = FakeAnalytics()
        PostHogSink(client: client).capture(.appOpened)
        #expect(client.calls.isEmpty)
    }

    @Test("Handled failures go to GlitchTip only, never PostHog")
    func failuresIgnored() {
        let client = FakeAnalytics()
        let sink = PostHogSink(client: client)
        sink.start(installID: UUID())
        sink.capture(TelemetryFailure(area: .driveWrite, error: CocoaError(.fileWriteOutOfSpace)))
        #expect(client.calls == ["setup"])
    }
}

@MainActor
final class FakeErrorReporting: ErrorReportingClient {
    var calls: [String] = []
    var tags: [String: String] = [:]

    func start(environment: String) { calls.append("start \(environment)") }
    func setUser(id: String) { calls.append("user \(id)") }
    func close() { calls.append("close") }
    func addBreadcrumb(category: String, message: String) { calls.append("breadcrumb \(category) \(message)") }
    func captureMessage(_ message: String, tags: [String: String]) {
        calls.append("message \(message)")
        self.tags = tags
    }
}

@MainActor
final class FakeAnalytics: AnalyticsClient {
    var calls: [String] = []
    var lastProperties: [String: Any]?

    func setup() { calls.append("setup") }
    func optIn() { calls.append("optIn") }
    func optOut() { calls.append("optOut") }
    func capture(_ event: String, distinctId: String, properties: [String: Any]) {
        calls.append("capture \(event) \(distinctId)")
        lastProperties = properties
    }
}

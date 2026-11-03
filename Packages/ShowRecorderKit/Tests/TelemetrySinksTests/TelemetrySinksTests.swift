import Foundation
import Sentry
import Telemetry
import Testing
@testable import TelemetrySinks

/// The app's sinks (ADR 0007, #1026): what the Sentry SDK is allowed to collect, and what PostHog receives.
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

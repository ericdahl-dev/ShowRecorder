import PostHog
import Sentry

// The only lines that call the Sentry and PostHog SDKs (ADR 0007, #1026). Each is a direct call with no logic, so a
// unit test could only check it by sending a real event: codecov.yml leaves this file out, and the sinks' logic is
// tested with fakes in TelemetrySinksTests. Checked on a device instead (Eric's TestFlight check on #1026).

@MainActor
final class SentrySDKClient: ErrorReportingClient {
    func start(environment: String) {
        SentrySDK.start { options in SentrySink.configure(options, environment: environment) }
    }

    func setUser(id: String) {
        SentrySDK.setUser(User(userId: id))
    }

    func close() {
        SentrySDK.close()
    }

    func addBreadcrumb(category: String, message: String) {
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    func captureMessage(_ message: String, tags: [String: String]) {
        SentrySDK.capture(message: message) { scope in
            for (key, value) in tags { scope.setTag(value: value, key: key) }
        }
    }
}

@MainActor
final class PostHogSDKClient: AnalyticsClient {
    func setup(filter: PostHogEventFilter) {
        let config = PostHogConfig(projectToken: PostHogSink.projectToken, host: PostHogSink.host)
        PostHogSink.configure(config)
        config.setBeforeSend([Self.beforeSend(filter)])
        PostHogSDK.shared.setup(config)
    }

    /// Made outside the main actor: the SDK calls it from whatever thread captured the event.
    private nonisolated static func beforeSend(_ filter: PostHogEventFilter) -> BeforeSendBlock {
        { event in
            let outgoing = PostHogOutgoingEvent(name: event.event, distinctId: event.distinctId, properties: event.properties)
            guard let kept = filter.filter(outgoing) else { return nil }
            event.distinctId = kept.distinctId
            event.properties = kept.properties
            return event
        }
    }

    func optIn() {
        PostHogSDK.shared.optIn()
    }

    func optOut() {
        PostHogSDK.shared.optOut()
    }

    func capture(_ event: String, distinctId: String, properties: [String: Any]) {
        PostHogSDK.shared.capture(event, distinctId: distinctId, properties: properties)
    }
}

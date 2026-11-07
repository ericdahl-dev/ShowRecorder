import Telemetry

/// Usage events from purchases (ADR 0007, #1026): what a purchase the operator made changed, from what was owned before
/// it and after. trial_started when it started the Trial, pro_bought when it made Pro owned (Pro, or a pack owner's
/// upgrade). Buying what is already owned changes nothing and sends nothing; a pack alone has no event. The app asks
/// only around its own purchases, not at launch, on Restore or on the App Store's later updates, so a restore or
/// another device's purchase isn't counted again.
public enum PurchaseTelemetry {
    public static func events(before: ProPurchases, after: ProPurchases) -> [TelemetryEvent] {
        var events: [TelemetryEvent] = []
        if before.trialStartedAt == nil, after.trialStartedAt != nil { events.append(.trialStarted) }
        if !before.ownsPro, after.ownsPro { events.append(.proBought) }
        return events
    }
}

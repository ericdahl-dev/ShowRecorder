import Foundation

/// Crash reports and usage (ADR 0007, #1026). Starts the sinks (GlitchTip and PostHog in the app) and hands them the
/// fixed list of events and handled failures, only while sharing is on and the build offers it
/// (`TelemetryAvailability`). Called from the Take session and the UI, never from the real-time audio path (ADR 0002).
@MainActor
public final class Telemetry {
    private let defaults: UserDefaults
    private let sinks: [any TelemetrySink]
    private let isAvailable: () -> Bool
    private var running = false

    /// `isAvailable` is asked on each `start()`: a Release build learns it is TestFlight only once StoreKit answers,
    /// so the app calls `start()` again then.
    public init(defaults: UserDefaults = .standard, sinks: [any TelemetrySink], isAvailable: @escaping () -> Bool) {
        self.defaults = defaults
        self.sinks = sinks
        self.isAvailable = isAvailable
    }

    /// Settings › "Share crash reports and usage".
    public var isSharing: Bool { TelemetryConsent.isOn(in: defaults) }

    /// Starts the sinks with the install ID, making one if needed. Does nothing if already running, if sharing is
    /// off or if the build doesn't offer it; then no install ID is made either.
    public func start() {
        guard !running, isSharing, isAvailable() else { return }
        let id = InstallID.current(in: defaults)
        for sink in sinks { sink.start(installID: id) }
        running = true
    }

    /// The Settings switch. Off stops the sinks and deletes the install ID; on starts them with a new one.
    public func setSharing(_ on: Bool) {
        TelemetryConsent.set(on, in: defaults)
        if on {
            start()
        } else {
            if running { for sink in sinks { sink.stop() } }
            running = false
            InstallID.delete(from: defaults)
        }
    }

    public func send(_ event: TelemetryEvent) {
        guard running else { return }
        for sink in sinks { sink.capture(event) }
    }

    /// A failure the app caught on purpose. An SDK reports only what escapes, so each branch that matters calls this.
    public func report(_ failure: TelemetryFailure) {
        guard running else { return }
        for sink in sinks { sink.capture(failure) }
    }
}

/// Where events and failures go: GlitchTip and PostHog in the app, a recorder in tests.
@MainActor
public protocol TelemetrySink: AnyObject {
    func start(installID: UUID)
    func stop()
    func capture(_ event: TelemetryEvent)
    func capture(_ failure: TelemetryFailure)
}

/// Settings › "Share crash reports and usage": on by default (ADR 0007).
public enum TelemetryConsent {
    static let key = "shareCrashReportsAndUsage"

    public static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public static func set(_ on: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key)
    }
}

/// A random UUID made on first use and kept in the app's settings, so a reinstall gets a new one. Never tied to a
/// name, an email, an Apple Account or a purchase. Turning sharing off deletes it.
public enum InstallID {
    static let key = "telemetryInstallID"

    /// The kept ID, making and keeping one if there is none.
    public static func current(in defaults: UserDefaults = .standard) -> UUID {
        if let id = stored(in: defaults) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }

    public static func stored(in defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    public static func delete(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

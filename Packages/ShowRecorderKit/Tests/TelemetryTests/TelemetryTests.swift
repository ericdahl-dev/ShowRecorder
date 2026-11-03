import Foundation
import Testing
@testable import Telemetry

/// Crash reports and usage (ADR 0007, #1026): on by default, one switch turns it off, keyed by a random install ID
/// that the switch deletes, and only a fixed list of events with no names, notes, paths or audio.
@MainActor
@Suite("Telemetry")
struct TelemetryTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TelemetryTests-\(UUID().uuidString)")!
    }

    private func makeTelemetry(
        _ defaults: UserDefaults, available: Bool = true
    ) -> (Telemetry, RecordingSink) {
        let sink = RecordingSink()
        let telemetry = Telemetry(defaults: defaults, sinks: [sink], isAvailable: { available })
        return (telemetry, sink)
    }

    @Test("Sharing is on by default, and the switch is remembered")
    func consentDefault() {
        let defaults = makeDefaults()
        #expect(TelemetryConsent.isOn(in: defaults))
        TelemetryConsent.set(false, in: defaults)
        #expect(!TelemetryConsent.isOn(in: defaults))
        TelemetryConsent.set(true, in: defaults)
        #expect(TelemetryConsent.isOn(in: defaults))
    }

    @Test("The install ID is made once and kept")
    func installIDIsStable() {
        let defaults = makeDefaults()
        let first = InstallID.current(in: defaults)
        #expect(InstallID.current(in: defaults) == first)
        #expect(InstallID.stored(in: defaults) == first)
    }

    @Test("Deleting the install ID means the next one is new")
    func installIDReset() {
        let defaults = makeDefaults()
        let first = InstallID.current(in: defaults)
        InstallID.delete(from: defaults)
        #expect(InstallID.stored(in: defaults) == nil)
        #expect(InstallID.current(in: defaults) != first)
    }

    @Test("start() starts every sink with the install ID, and events go to them with it")
    func sendsWhenOn() {
        let defaults = makeDefaults()
        let (telemetry, sink) = makeTelemetry(defaults)
        telemetry.start()
        let id = InstallID.stored(in: defaults)
        #expect(id != nil)
        #expect(sink.started == [id!])
        telemetry.send(.appOpened)
        #expect(sink.events.map(\.name) == ["app_opened"])
    }

    @Test("With the switch off, start() starts nothing, sends nothing and makes no install ID")
    func silentWhenOff() {
        let defaults = makeDefaults()
        TelemetryConsent.set(false, in: defaults)
        let (telemetry, sink) = makeTelemetry(defaults)
        telemetry.start()
        telemetry.send(.appOpened)
        telemetry.report(TelemetryFailure(area: .deleteShow, error: CocoaError(.fileNoSuchFile)))
        #expect(sink.started.isEmpty)
        #expect(sink.events.isEmpty)
        #expect(sink.failures.isEmpty)
        #expect(InstallID.stored(in: defaults) == nil)
    }

    @Test("Where the build doesn't offer it, nothing starts or sends, even with the switch on")
    func silentWhenUnavailable() {
        let defaults = makeDefaults()
        let (telemetry, sink) = makeTelemetry(defaults, available: false)
        telemetry.start()
        telemetry.send(.appOpened)
        #expect(sink.started.isEmpty)
        #expect(sink.events.isEmpty)
        #expect(InstallID.stored(in: defaults) == nil)
    }

    @Test("Turning the switch off stops the sinks and deletes the install ID; on again makes a new one")
    func switchOffAndOn() {
        let defaults = makeDefaults()
        let (telemetry, sink) = makeTelemetry(defaults)
        telemetry.start()
        let first = InstallID.stored(in: defaults)!

        telemetry.setSharing(false)
        #expect(!TelemetryConsent.isOn(in: defaults))
        #expect(sink.stops == 1)
        #expect(InstallID.stored(in: defaults) == nil)
        telemetry.send(.appOpened)
        #expect(sink.events.isEmpty)

        telemetry.setSharing(true)
        let second = InstallID.stored(in: defaults)
        #expect(second != nil && second != first)
        #expect(sink.started == [first, second!])
        telemetry.send(.appOpened)
        #expect(sink.events.count == 1)
    }

    @Test("A handled failure goes to the sinks when sharing is on")
    func reportsFailures() {
        let defaults = makeDefaults()
        let (telemetry, sink) = makeTelemetry(defaults)
        telemetry.start()
        telemetry.report(TelemetryFailure(area: .driveWrite, error: CocoaError(.fileWriteOutOfSpace)))
        #expect(sink.failures.map(\.area) == [.driveWrite])
    }
}

@Suite("Telemetry events")
struct TelemetryEventTests {
    @Test("Each event has a fixed snake_case name")
    func names() {
        let events: [(TelemetryEvent, String)] = [
            (.appOpened, "app_opened"),
            (.takeStarted(channelCount: 18, destinations: .both, mixerFamily: "xair"), "take_started"),
            (.takeStopped(seconds: 60, channelCount: 18, dropouts: 0, cause: .operatorStop), "take_stopped"),
            (.showCreated, "show_created"),
            (.showDeleted, "show_deleted"),
            (.driveConnected, "drive_connected"),
            (.driveLost, "drive_lost"),
            (.mixerLinkConnected(mixerFamily: "x32"), "mixer_link_connected"),
            (.trialStarted, "trial_started"),
            (.proBought, "pro_bought"),
        ]
        for (event, name) in events { #expect(event.name == name) }
    }

    @Test("A Take carries counts and kinds only")
    func takeProperties() {
        let started = TelemetryEvent.takeStarted(channelCount: 18, destinations: .driveOnly, mixerFamily: "xair")
        #expect(started.properties == [
            "channel_count": .int(18), "destinations": .string("drive_only"), "mixer_family": .string("xair"),
        ])
        let noMixer = TelemetryEvent.takeStarted(channelCount: 2, destinations: .device, mixerFamily: nil)
        #expect(noMixer.properties["mixer_family"] == nil)

        let stopped = TelemetryEvent.takeStopped(seconds: 3600, channelCount: 18, dropouts: 2, cause: .watch)
        #expect(stopped.properties == [
            "seconds": .int(3600), "channel_count": .int(18), "dropouts": .int(2), "cause": .string("watch"),
        ])
    }

    @Test("Events with nothing to add carry no properties")
    func emptyProperties() {
        #expect(TelemetryEvent.appOpened.properties.isEmpty)
        #expect(TelemetryEvent.proBought.properties.isEmpty)
    }
}

@Suite("Telemetry failures")
struct TelemetryFailureTests {
    @Test("A failure keeps the error's type, domain and code, never its message, which can hold a file path")
    func noMessage() {
        let path = "/private/var/mobile/Shows/Sunday Service/Take 01/Kick.wav"
        let error = NSError(
            domain: NSCocoaErrorDomain, code: 640,
            userInfo: [NSFilePathErrorKey: path, NSLocalizedDescriptionKey: "Couldn't write \(path)"]
        )
        let failure = TelemetryFailure(area: .driveWrite, error: error)
        #expect(failure.area == .driveWrite)
        #expect(failure.domain == NSCocoaErrorDomain)
        #expect(failure.code == 640)
        #expect(!failure.errorType.isEmpty)
        #expect(!failure.summary.contains(path))
        #expect(!failure.summary.contains("Sunday"))
        #expect(failure.summary.contains("drive_write"))
    }

    @Test("Each area has a fixed name")
    func areas() {
        #expect(TelemetryFailure.Area.allCases.map(\.rawValue) == [
            "drive_write", "repair", "move_to_drive", "delete_show",
        ])
    }
}

/// Records what Telemetry hands its sinks.
@MainActor
final class RecordingSink: TelemetrySink {
    var started: [UUID] = []
    var stops = 0
    var events: [TelemetryEvent] = []
    var failures: [TelemetryFailure] = []

    func start(installID: UUID) { started.append(installID) }
    func stop() { stops += 1 }
    func capture(_ event: TelemetryEvent) { events.append(event) }
    func capture(_ failure: TelemetryFailure) { failures.append(failure) }
}

import Destinations
import Foundation
import Telemetry
import Testing

@testable import Recording

/// Usage events from the Drive (ADR 0007, #1026): drive_connected once per connect and drive_lost once per loss, not
/// on every re-read of the Drive's status.
@MainActor
@Suite("Drive telemetry")
struct DriveTelemetryTests {
    func available(_ bytes: Int64 = 60_000, name: String = "SSD") -> DriveStatus {
        .available(Drive(folder: URL(filePath: "/Volumes/\(name)"), name: name, availableBytes: bytes))
    }

    let gone = DriveStatus.unavailable(.notConnected(name: "SSD"))

    @Test("The status found at launch is where it starts: a Drive already there isn't a connect")
    func launchIsTheBaseline() {
        var sent: [TelemetryEvent] = []
        let telemetry = DriveTelemetry(send: { sent.append($0) })
        telemetry.observe(available())
        #expect(sent.isEmpty)
    }

    @Test("A Drive that comes back sends drive_connected once, however often its status is read again")
    func connectedOnce() {
        var sent: [TelemetryEvent] = []
        let telemetry = DriveTelemetry(send: { sent.append($0) })
        telemetry.observe(gone)
        telemetry.observe(available(60_000))
        telemetry.observe(available(59_000))
        telemetry.observe(available(58_000))
        #expect(sent == [.driveConnected])
    }

    @Test("Choosing a Drive for the first time is a connect")
    func firstChoice() {
        var sent: [TelemetryEvent] = []
        let telemetry = DriveTelemetry(send: { sent.append($0) })
        telemetry.observe(.notChosen)
        telemetry.observe(available())
        #expect(sent == [.driveConnected])
    }

    @Test("A Drive that goes away sends drive_lost once; it coming back sends drive_connected again")
    func lostOnceThenBack() {
        var sent: [TelemetryEvent] = []
        let telemetry = DriveTelemetry(send: { sent.append($0) })
        telemetry.observe(available())
        telemetry.observe(gone)
        telemetry.observe(gone)
        telemetry.observe(available())
        #expect(sent == [.driveLost, .driveConnected])
    }

    @Test("Choosing another Drive folder while one is there, or forgetting the folder, is neither")
    func choiceChanges() {
        var sent: [TelemetryEvent] = []
        let telemetry = DriveTelemetry(send: { sent.append($0) })
        telemetry.observe(available(name: "SSD"))
        telemetry.observe(available(name: "Other"))
        telemetry.observe(.notChosen)
        #expect(sent.isEmpty)
    }
}

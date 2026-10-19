import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// A Take that starts without its Drive says why, on screen and in `Take.json` (#814): the Drive chip can read connected
/// while the press finds no Drive, and a Drive that fails at the press used to fall back to the Device without a word.
@MainActor
@Suite("Why a Take started without its Drive")
struct DriveNoteTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "DriveNoteTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let take = "2026-10-06 Show/Take 01"

    struct ReadOnly: LocalizedError {
        var errorDescription: String? { "the disk is read-only" }
    }

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorded(
        access: Bool, problem: String? = nil, failingStems: Bool = false
    ) throws -> (Recorder, TakeMetadata) {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { access ? DriveAccess(folder: drive) : nil }, driveProblem: { problem },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                if failingStems, url.path.hasPrefix(drive.path) { throw ReadOnly() }
                return try StemWriter.open(url: url, info: info, resumingAt: resuming)
            }, destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        let metadata = try TakeMetadata.read(fromTakeFolder: device.appending(path: take))
        return (recorder, metadata)
    }

    @Test("A press that finds no Drive says why in the notice and in the Device's Take.json")
    func noDriveAtThePress() throws {
        let (recorder, metadata) = try recorded(access: false, problem: "The Drive folder \"T7\" isn't available.")

        #expect(recorder.isRecording)
        #expect(recorder.driveNotice?.contains("T7") == true)
        #expect(metadata.driveNote?.contains("T7") == true)
    }

    @Test("No Drive connected, and no reason from the app: Take.json still says there was none at the press, the screen says nothing more")
    func noDriveChosen() throws {
        let (recorder, metadata) = try recorded(access: false)

        #expect(recorder.isRecording)
        #expect(recorder.driveNotice == nil, "no new text on screen")
        #expect(metadata.driveNote?.contains("No Drive") == true, "but the file says so, for a report that asks why the Drive Copy starts late")
    }

    @Test("A Take the settings send to the Device by choice has nothing to explain: no note")
    func deviceByChoiceHasNoNote() throws {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            destinationCheckInterval: nil)
        recorder.recordTo = .device
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))
        try recorder.startTake()

        #expect(recorder.driveNotice == nil)
        #expect(try TakeMetadata.read(fromTakeFolder: device.appending(path: take)).driveNote == nil)
    }

    @Test("A Drive that fails at the press still records to the Device, and the swallowed error is in the notice and Take.json (#315)")
    func driveFailsAtThePress() throws {
        let (recorder, metadata) = try recorded(access: true, failingStems: true)

        #expect(recorder.isRecording)
        #expect(recorder.driveNotice?.contains("the disk is read-only") == true)
        #expect(metadata.driveNote?.contains("the disk is read-only") == true)
    }

    @Test("A press with a healthy Drive has no notice and no note")
    func healthyDrive() throws {
        let (recorder, metadata) = try recorded(access: true)

        #expect(recorder.driveNotice == nil)
        #expect(metadata.driveNote == nil)
    }

    final class Flag: @unchecked Sendable {
        var on = false
    }

    @Test("The same Recorder's next press forgets the last one's notice")
    func noticeIsPerPress() async throws {
        let available = Flag()
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { available.on ? DriveAccess(folder: drive) : nil }, driveProblem: { "gone" },
            now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))
        try recorder.startTake()
        #expect(recorder.driveNotice != nil)
        try await recorder.stopTake()
        #expect(recorder.driveNotice != nil, "kept until the next press")

        available.on = true
        try recorder.startTake()

        #expect(recorder.driveNotice == nil)
        try await recorder.stopTake()
    }

    @Test("A Pro Take whose Drive wasn't there at the press still gets it later, and the reason goes once it has joined")
    func proTakeJoinsTheDriveLater() async throws {
        let available = Flag()
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { available.on ? DriveAccess(folder: drive) : nil }, driveProblem: { "still mounting" },
            now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake(allowance: Entitlement.allowance(for: .pro, channelCount: 1))
        audio.deliver([Array(repeating: 0.25, count: 480)])
        #expect(recorder.driveNotice?.contains("still mounting") == true)

        available.on = true
        await recorder.checkDestinations()

        #expect(recorder.copies[.drive] != .missing, "the Drive joined")
        #expect(recorder.driveNotice == nil, "so it no longer says it wasn't there")
        try await recorder.stopTake()
    }

    @Test("A Free Take starts without the Drive and the Drive never joins it mid-Take: the Drive Copy is Pro")
    func freeTakeNeverJoinsTheDrive() async throws {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake(allowance: Entitlement.allowance(for: .free, channelCount: 1))
        audio.deliver([Array(repeating: 0.25, count: 480)])

        await recorder.checkDestinations()
        audio.deliver([Array(repeating: 0.25, count: 480)])
        await recorder.checkDestinations()

        #expect(recorder.driveNotice?.contains("Pro") == true, "the notice says the Drive Copy is Pro")
        #expect(recorder.copies[.drive] == .missing, "no Drive Copy joined")
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: take).path), "nothing created on the Drive")
        try await recorder.stopTake()
    }

    @Test("A Pro Take with the Device chosen never gets the Drive mid-Take, and has nothing to explain (#805)")
    func deviceChosenNeverJoinsTheDrive() async throws {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            destinationCheckInterval: nil)
        recorder.recordTo = .device
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake(allowance: Entitlement.allowance(for: .pro, channelCount: 1))
        audio.deliver([Array(repeating: 0.25, count: 480)])

        await recorder.checkDestinations()
        audio.deliver([Array(repeating: 0.25, count: 480)])
        await recorder.checkDestinations()

        #expect(recorder.driveNotice == nil, "the Device by choice is no problem")
        #expect(recorder.copies[.drive] == .missing, "no Drive Copy joined")
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: take).path), "nothing created on the Drive")
        try await recorder.stopTake()
    }

    @Test("The warning for a Take without a Drive carries the reason")
    func alertCarriesTheNote() throws {
        let alert = try #require(DestinationAlert.make(
            copies: takeCopies(device: .recording, drive: .missing), driveNote: "The Drive failed at the press: the disk is read-only."))

        #expect(alert.text.contains("No Drive"))
        #expect(alert.text.contains("the disk is read-only"))
    }

    @Test("Free has no Drive Copy to warn about: no 'No Drive' alert, though the Take's note stays in Take.json (Eric, #814)")
    func noAlertOnFree() throws {
        #expect(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .missing), driveCopyAllowed: false) == nil)
        #expect(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .missing), driveCopyAllowed: true) != nil)
    }

    @Test("A Free Take with a Drive connected says its Drive Copy isn't allowed, and keeps the Pro note in Take.json")
    func freeTakeIsMarkedNotAllowed() throws {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            destinationCheckInterval: nil)
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))
        try recorder.startTake(allowance: Entitlement.allowance(for: .free, channelCount: 1))

        #expect(!recorder.driveCopyAllowed)
        #expect(try TakeMetadata.read(fromTakeFolder: device.appending(path: take)).driveNote?.contains("Pro") == true)
    }

    @Test("A Pro Take may have a Drive Copy")
    func proTakeIsAllowed() throws {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            destinationCheckInterval: nil)
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))
        try recorder.startTake(allowance: Entitlement.allowance(for: .pro, channelCount: 1))

        #expect(recorder.driveCopyAllowed)
    }

    @Test("Without a note the warning reads as before")
    func alertWithoutNote() throws {
        let alert = try #require(DestinationAlert.make(copies: takeCopies(device: .recording, drive: .missing)))

        #expect(alert.text == "No Drive. Recording to the Device only.")
    }
}

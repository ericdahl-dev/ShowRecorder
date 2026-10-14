import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#630): Drive only Takes move to the Drive on their own: once moving is offered at launch, after Stop,
/// and when the Drive connects; never during a Take.
extension DriveOnlyTakeTests {
    /// A Drive only Take of 4 800 frames recorded with no Drive, by a recorder that then quits; the Drive is connected.
    func leaveDeviceOnlyTake(_ switched: DriveSwitch) async throws {
        let recorder = try await recordDeviceOnlyTake(switched)
        recorder.disarm()
    }

    @Test("Once moving is offered, a launch with the Drive moves the Drive only Takes left on the Device (#630)")
    func launchMoves() async throws {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        let launched = recorder(drive: switched)

        launched.movesDriveOnlyTakes = true
        await launched.waitForMoves()

        #expect(launched.driveOnlyMoves == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path))
    }

    @Test("Where moving isn't offered, the Drive connecting moves nothing (#630)")
    func notOfferedMovesNothing() async throws {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        let launched = recorder(drive: switched)

        launched.driveMayHaveConnected()
        await launched.waitForMoves()

        #expect(launched.driveOnlyMoves.isEmpty)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: take).path))
    }

    @Test("The Drive connecting during a Take moves nothing until the Take stops; then the Take moves (#630)")
    func movesAfterStopNotDuringATake() async throws {
        let switched = DriveSwitch()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(drive: switched)
        recorder.movesDriveOnlyTakes = true
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        switched.connected = true
        recorder.driveMayHaveConnected()
        await recorder.waitForMoves()
        #expect(recorder.driveOnlyMoves.isEmpty, "nothing moves during a Take")

        try recorder.stopTake()
        await recorder.waitForRepair()
        await recorder.waitForMoves()

        #expect(recorder.driveOnlyMoves == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(try driveSamples(frames: 4_800) == (0..<4_800).map { counting()($0, 0) })
    }

    @Test("The Drive connecting twice moves each Take once (#630)")
    func triggersCoalesce() async throws {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        let launched = recorder(drive: switched)
        launched.movesDriveOnlyTakes = true

        launched.driveMayHaveConnected()
        launched.driveMayHaveConnected()
        await launched.waitForMoves()

        #expect(launched.driveOnlyMoves.map(\.outcome) == [.moved])
    }

    @Test("While a move runs it shows, and deleting a Show, Take or channel is refused until it ends (#630)")
    func editsWaitForAMove() async throws {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        let launched = recorder(drive: switched)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let moving = Task { await launched.moveDriveOnlyTakes(shouldStop: { gate.wait(); return false }) }
        try await waitUntil { launched.isMoving }

        for outcome in [
            launched.deleteShow(named: "2026-10-06 Show", from: [.device]),
            launched.deleteTake(1, ofShow: "2026-10-06 Show", from: [.device]),
            launched.deleteChannel(1, inTake: 1, ofShow: "2026-10-06 Show", from: [.device]),
        ] {
            #expect(outcome.deleted.isEmpty)
            #expect(outcome.failed.map(\.reason) == ["Takes are moving to the Drive."])
        }
        gate.open()
        _ = await moving.value
        #expect(!launched.isMoving)
        #expect(launched.driveOnlyMoves.map(\.outcome) == [.moved])
    }

    @Test("A Take the move leaves where it is, such as one of another recording on the Drive, is reported with why (#630)")
    func skipsAreReported() async throws {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        // The Drive has a Take 01 of another recording.
        try FileManager.default.createDirectory(at: drive.appending(path: take), withIntermediateDirectories: true)
        var other = try TakeMetadata.read(fromTakeFolder: device.appending(path: take))
        other.startedAt = other.startedAt.addingTimeInterval(60)
        try other.write(to: drive.appending(path: take))
        let launched = recorder(drive: switched)

        launched.movesDriveOnlyTakes = true
        await launched.waitForMoves()

        #expect(launched.driveOnlySkips.map(\.kind) == [.skipped(.anotherRecording)])
        #expect(launched.driveOnlyMoves.isEmpty)
    }

    /// Whether a move has reached the point a test holds it at.
    final class Held: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var entered: Bool { lock.withLock { value } }
        func enter() { lock.withLock { value = true } }
    }

    /// A Drive only Take with a Marker, recorded with no Drive; the Drive is then connected.
    func recordDeviceOnlyTakeWithMarker(_ switched: DriveSwitch) async throws -> Recorder {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(drive: switched)
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        recorder.addMarker()
        try await deliverBlocks(1, from: 4_800, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()
        switched.connected = true
        return recorder
    }

    @Test("A Take started and stopped while a move is held within a Stem stops the move, and that Take's Repair runs next (#630)")
    func takeDuringAMoveStopsIt() async throws {
        let switched = DriveSwitch()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = try await recordDeviceOnlyTake(switched)
        try recorder.arm(audio)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let latch = recorder.moveStop.latch()
        let held = Held()
        let moving = Task { await recorder.moveDriveOnlyTakes(shouldStop: { held.enter(); gate.wait(); return latch() }) }
        try await waitUntil { held.entered }

        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        gate.open()

        let results = await moving.value
        #expect(results.map(\.outcome) == [.stopped], "\(results)")
        await recorder.waitForRepair()
        #expect(FileManager.default.fileExists(atPath: device.appending(path: take).path), "Take 01 waits for the next move")
        #expect(recorder.copies[.drive] == .complete, "Take 02, recorded to the Drive, ended")
    }

    @Test("Renaming the last Take's Marker while a move is held waits for it, and the Drive's Take.json then has the new name (#630)")
    func lastTakeRenameWaitsForAMove() async throws {
        let switched = DriveSwitch()
        let recorder = try await recordDeviceOnlyTakeWithMarker(switched)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let moving = Task { await recorder.moveDriveOnlyTakes(shouldStop: { gate.wait(); return false }) }
        try await waitUntil { recorder.isMoving }

        let renaming = Task { await recorder.renameLastTakeMarker(at: 0, to: "Intro") }
        try await Task.sleep(for: .milliseconds(200))
        #expect(try TakeMetadata.read(fromTakeFolder: device.appending(path: take)).markers.map(\.name) == ["Marker 1"], "not renamed while moving")
        gate.open()
        #expect(await moving.value.map(\.outcome) == [.moved])
        let outcome = await renaming.value

        #expect(outcome.renamed == [.drive])
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).markers.map(\.name) == ["Intro"])
    }

    @Test("Renaming an older Take's Marker on Show detail while a move is held waits for it (#630)")
    func showDetailRenameWaitsForAMove() async throws {
        let switched = DriveSwitch()
        let recorder = try await recordDeviceOnlyTakeWithMarker(switched)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let moving = Task { await recorder.moveDriveOnlyTakes(shouldStop: { gate.wait(); return false }) }
        try await waitUntil { recorder.isMoving }

        let renaming = Task { await recorder.renameMarker(at: 0, to: "Intro", inTake: 1, ofShow: "2026-10-06 Show", allowsProExtras: true) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(try TakeMetadata.read(fromTakeFolder: device.appending(path: take)).markers.map(\.name) == ["Marker 1"], "not renamed while moving")
        gate.open()
        _ = await moving.value
        let outcome = await renaming.value

        #expect(outcome.renamed == [.drive])
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).markers.map(\.name) == ["Intro"])
    }

    @Test("The Drive reported as connected several times before a move starts makes one scan (#630)")
    func repeatedTriggersMakeOneScan() async throws {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        let launched = recorder(drive: switched)
        launched.movesDriveOnlyTakes = true

        launched.driveMayHaveConnected()
        launched.driveMayHaveConnected()
        await launched.waitForMoves()

        #expect(launched.driveOnlyScans == 1)
    }

    @Test("A move started while a Show detail rename is in flight waits for it to finish (#630)")
    func moveWaitsForARename() async throws {
        let switched = DriveSwitch()
        let recorder = try await recordDeviceOnlyTakeWithMarker(switched)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let held = Held()
        recorder.beforeDetachedRename = { held.enter(); gate.wait() }
        let renaming = Task { await recorder.renameMarker(at: 0, to: "Intro", inTake: 1, ofShow: "2026-10-06 Show", allowsProExtras: true) }
        try await waitUntil { held.entered }

        let moving = Task { await recorder.moveDriveOnlyTakes() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(recorder.driveOnlyMoves.isEmpty, "the move waits for the rename")
        #expect(FileManager.default.fileExists(atPath: device.appending(path: take).path))
        gate.open()

        #expect(await renaming.value.renamed == [.device])
        #expect(await moving.value.map(\.outcome) == [.moved])
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).markers.map(\.name) == ["Intro"])
    }
}

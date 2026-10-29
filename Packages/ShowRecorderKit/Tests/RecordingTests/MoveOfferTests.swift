import AudioIO
import Foundation
@testable import Recording
import Testing

/// Record to (#805): with the Device chosen, a Drive connecting while Drive only Takes wait on the Device asks the
/// operator before moving them, once per Drive connection.
extension DriveOnlyTakeTests {
    /// A recorder with the Device chosen, launched after a Drive only Take was left on the Device; the Drive is connected.
    func deviceChosenWithATakeWaiting() async throws -> Recorder {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        let launched = recorder(drive: switched)
        launched.recordTo = .device
        launched.movesDriveOnlyTakes = true
        await launched.waitForMoves()
        return launched
    }

    @Test("Device chosen: a Drive connecting with Drive only Takes waiting asks and moves nothing (#805)")
    func offerAsksWithTheDeviceChosen() async throws {
        let launched = try await deviceChosenWithATakeWaiting()

        #expect(launched.moveOffer == 1)
        #expect(launched.driveOnlyMoves.isEmpty)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: take).path))
    }

    @Test("Answering Move moves the waiting Drive only Takes (#805)")
    func offerAnsweredMove() async throws {
        let launched = try await deviceChosenWithATakeWaiting()

        launched.answerMoveOffer(move: true)
        await launched.waitForMoves()

        #expect(launched.moveOffer == nil)
        #expect(launched.driveOnlyMoves == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path))
    }

    @Test("Answering Not now leaves them, and the same Drive connection doesn't ask again (#805)")
    func offerAnsweredNotNow() async throws {
        let launched = try await deviceChosenWithATakeWaiting()

        launched.answerMoveOffer(move: false)
        launched.driveMayHaveConnected()
        await launched.waitForMoves()

        #expect(launched.moveOffer == nil)
        #expect(launched.driveOnlyMoves.isEmpty)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: take).path))
    }

    @Test("After the Drive goes, its next connection asks again (#805)")
    func offerAsksAgainAfterTheDriveWentAway() async throws {
        let launched = try await deviceChosenWithATakeWaiting()
        launched.answerMoveOffer(move: false)

        launched.driveWentAway()
        launched.driveMayHaveConnected()
        await launched.waitForMoves()

        #expect(launched.moveOffer == 1)
        #expect(launched.driveOnlyMoves.isEmpty)
    }

    @Test("Both or Drive chosen: the Drive connecting moves the Takes as before, without asking (#805)",
          arguments: [RecordTo.both, .drive])
    func offerNotMadeWithBothOrDriveChosen(choice: RecordTo) async throws {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        let launched = recorder(drive: switched)
        launched.recordTo = choice

        launched.movesDriveOnlyTakes = true
        await launched.waitForMoves()

        #expect(launched.moveOffer == nil)
        #expect(launched.driveOnlyMoves == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
    }

    @Test("Device chosen: a move a crash cut off is still finished, without asking (#805)")
    func offerNotNeededToFinishACutOffMove() async throws {
        let switched = DriveSwitch()
        let recorder = try await recordDeviceOnlyTake(switched)
        #expect(await recorder.moveDriveOnlyTakes().map(\.outcome) == [.moved])
        // As a crash leaves it: the Take set aside on the Device, not yet deleted.
        let setAside = device.appending(path: "2026-10-06 Show/.moved Take 01")
        try FileManager.default.copyItem(at: drive.appending(path: take), to: setAside)
        recorder.recordTo = .device

        let results = await recorder.moveDriveOnlyTakes()

        #expect(results == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(!FileManager.default.fileExists(atPath: setAside.path))
        #expect(recorder.moveOffer == nil)
    }

    @Test("Move, then the Drive going before the move runs: the next connection asks again (#805)")
    func offerMoveAnswerEndsWithTheConnection() async throws {
        let launched = try await deviceChosenWithATakeWaiting()

        launched.answerMoveOffer(move: true)
        launched.driveWentAway()
        await launched.waitForMoves()

        #expect(launched.moveOffer == 1)
        #expect(launched.driveOnlyMoves.isEmpty)
    }

    @Test("A Move answer lasts the connection: a move a Take stopped finishes later without asking (#805)")
    func offerMoveAnswerOutlivesAStoppedMove() async throws {
        let launched = try await deviceChosenWithATakeWaiting()
        // The test runs the moves itself.
        launched.movesDriveOnlyTakes = false
        launched.answerMoveOffer(move: true)

        let stopped = await launched.moveDriveOnlyTakes(shouldStop: { true })
        #expect(!stopped.contains { $0.outcome == .moved })
        #expect(FileManager.default.fileExists(atPath: device.appending(path: take).path))

        let results = await launched.moveDriveOnlyTakes()

        #expect(results.map(\.outcome) == [.moved])
        #expect(launched.moveOffer == nil)
    }

    @Test("A question left unanswered clears once the Takes move for another reason (#805)")
    func offerClearsWhenTheTakesMove() async throws {
        let launched = try await deviceChosenWithATakeWaiting()

        launched.recordTo = .both
        launched.driveMayHaveConnected()
        await launched.waitForMoves()

        #expect(launched.driveOnlyMoves.map(\.outcome) == [.moved])
        #expect(launched.moveOffer == nil)
    }

    @Test("Device chosen: a Device Copy the Drive already holds is removed without asking (#805)")
    func offerNotMadeForLeftoverCopies() async throws {
        let recorder = try await recordJoinMidTake()
        recorder.recordTo = .device

        let results = await recorder.moveDriveOnlyTakes()

        #expect(results.map(\.outcome) == [.moved])
        #expect(recorder.moveOffer == nil)
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path))
    }

    @Test("Device chosen: the question counts only Takes not yet on the Drive; leftover Copies go anyway (#805)")
    func offerCountsOnlyTakesNotOnTheDrive() async throws {
        let switched = DriveSwitch()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(drive: switched)
        try recorder.getReady(audio)
        // Take 01 with no Drive; Take 02 joined by the Drive mid-Take, so the Drive holds it whole after Repair.
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        switched.connected = true
        await recorder.checkDestinations()
        try await deliverBlocks(10, from: 4_800, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        recorder.recordTo = .device

        let results = await recorder.moveDriveOnlyTakes()

        #expect(results == [.init(show: "2026-10-06 Show", take: 2, outcome: .moved)])
        #expect(recorder.moveOffer == 1)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: take).path))
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 02").path))
    }

    @Test("A question left unanswered counts the Takes still waiting, when that changes before the answer (#805)")
    func offerCountFollowsTheWaitingTakes() async throws {
        let switched = DriveSwitch()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(drive: switched)
        try recorder.getReady(audio)
        // Two Drive only Takes, both recorded with no Drive, so both wait on the Device.
        for _ in 1...2 {
            try recorder.startTake()
            try await deliverBlocks(10, to: audio, recorder, sample: counting())
            try await recorder.stopTake()
            await recorder.waitForRepair()
        }
        switched.connected = true
        recorder.recordTo = .device
        _ = await recorder.moveDriveOnlyTakes()
        #expect(recorder.moveOffer == 2)

        try FileManager.default.removeItem(at: device.appending(path: "2026-10-06 Show/Take 02"))
        _ = await recorder.moveDriveOnlyTakes()

        #expect(recorder.moveOffer == 1)
    }

    @Test("Device chosen: a Drive connecting during a Take asks only after Stop (#805)")
    func offerWaitsForStop() async throws {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        switched.connected = false
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let launched = recorder(drive: switched)
        launched.recordTo = .device
        launched.movesDriveOnlyTakes = true
        try launched.getReady(audio)
        try launched.startTake()
        try await deliverBlocks(10, to: audio, launched, sample: counting())

        switched.connected = true
        launched.driveMayHaveConnected()
        await launched.waitForMoves()
        #expect(launched.moveOffer == nil, "never during a Take")

        try await launched.stopTake()
        await launched.waitForRepair()
        await launched.waitForMoves()

        #expect(launched.moveOffer == 1)
        #expect(launched.driveOnlyMoves.isEmpty)
    }

    @Test("Asking keeps what the move before it reported (#805)")
    func offerKeepsTheEarlierReport() async throws {
        let switched = DriveSwitch()
        try await leaveDeviceOnlyTake(switched)
        let launched = recorder(drive: switched)
        _ = await launched.moveDriveOnlyTakes(shouldStop: { true })
        let before = launched.moveReport.entries
        #expect(!before.isEmpty)
        launched.recordTo = .device

        _ = await launched.moveDriveOnlyTakes()

        #expect(launched.moveOffer == 1)
        #expect(launched.moveReport.entries == before)
    }
}

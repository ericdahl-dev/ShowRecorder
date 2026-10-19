import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

/// Copies of a Take (#550): the one answer the screens read about each Destination's Copy, from the Recorder.
extension GapTests {
    @Test("While a Take runs, each Copy says it's recording")
    func copiesWhileRecording() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())

        #expect(recorder.copies.isRunning)
        #expect(recorder.copies[.device] == .recording)
        #expect(recorder.copies[.drive] == .recording)
        try await recorder.stopTake()
    }

    @Test("With no Drive at record, the Drive's Copy is missing")
    func copiesNoDrive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()

        #expect(recorder.copies[.device] == .recording)
        #expect(recorder.copies[.drive] == .missing)
        try await recorder.stopTake()
    }

    @Test("A Copy retired for low space reads full while the Take runs; one that failed reads interrupted (#560)")
    func retiredForSpaceReadsFull() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let free = FreeSpace(device: 100_000_000, drive: 100_000_000)
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            freeSpace: { free.bytes(at: $0) }, destinationCheckInterval: .milliseconds(10))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder)
        free.drive = 5_000_000
        try await waitUntil { recorder.copies[.drive] == .full }
        #expect(recorder.copies[.device] == .recording)
        #expect(recorder.copies.full == [.drive])
        #expect(recorder.copies.stopped.isEmpty)
        try await recorder.stopTake()
    }

    @Test("Once the Take has ended, each Copy says how it ended: the Drive that came back is Repaired")
    func copiesAfterTheTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        #expect(recorder.copies[.drive] == .interrupted)
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(!recorder.copies.isRunning)
        #expect(recorder.copies[.device] == .complete)
        #expect(recorder.copies[.drive] == .repaired)
    }

    @Test("A Take that ended with no Drive leaves the Drive's Copy missing")
    func copiesAfterNoDrive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(recorder.copies[.device] == .complete)
        #expect(recorder.copies[.drive] == .missing)
    }

    @Test("While the next Take runs, its Copies read their running state, not how the last Take ended")
    func copiesDuringTheNextTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [])
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(recorder.copies[.drive] == .complete)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        #expect(recorder.copies[.drive] == .recording)
        try await recorder.stopTake()
    }

    @Test("Armed, before any Take, the Recorder has no Take running and every Copy missing")
    func copiesArmedBeforeAnyTake() throws {
        let recorder = recorder(failing: [])
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))

        #expect(!recorder.copies.isRunning)
        #expect(recorder.copies[.device] == .missing)
        #expect(recorder.copies[.drive] == .missing)
    }

    @Test("A Device that failed mid-Take ends Repaired from the Drive, which ends complete")
    func copiesAfterTheDeviceFails() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.device])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.device] == .interrupted }
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(recorder.copies[.device] == .repaired)
        #expect(recorder.copies[.drive] == .complete)
    }

    @Test("A Drive that joins mid-Take is missing until it joins; after, the Device is complete and the Drive Repaired")
    func copiesWhenTheDriveJoins() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let available = DriveSwitch()
        let recorder = Recorder(deviceFolder: device, driveFolder: { available.folder.map { DriveAccess(folder: $0) } },
                                now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        #expect(recorder.copies[.drive] == .missing)
        available.folder = drive
        await recorder.checkDestinations()
        #expect(recorder.copies[.drive] == .recording)
        try await deliverBlocks(5, from: 4_800, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(recorder.copies[.device] == .complete)
        #expect(recorder.copies[.drive] == .repaired)
    }

    @Test("Before any Take: none running, every Copy missing, none stopped")
    func noTake() {
        #expect(!TakeCopies.none.isRunning)
        #expect(DestinationKind.allCases.allSatisfy { TakeCopies.none[$0] == .missing })
        #expect(TakeCopies.none.stopped.isEmpty)
    }

    @Test("A refreshed snapshot holds while the Take is as it was; once one has started or stopped, the Recorder's own")
    func snapshotUntilTheTakeChanges() {
        let running = takeCopies(running: true, device: .recording, drive: .interrupted)
        let fresh = takeCopies(running: true, device: .recording, drive: .recording)
        #expect(running.current(isRecording: true, fresh) == running)
        #expect(TakeCopies.none.current(isRecording: true, fresh) == fresh, "a Take started since: no stale words")
        let ended = takeCopies(running: false, device: .complete, drive: .hasGaps)
        #expect(running.current(isRecording: false, ended) == ended, "the Take stopped since")
    }
}

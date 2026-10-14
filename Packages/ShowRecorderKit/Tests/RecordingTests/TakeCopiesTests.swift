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
        try recorder.stopTake()
    }

    @Test("With no Drive at record, the Drive's Copy is missing")
    func copiesNoDrive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()

        #expect(recorder.copies[.device] == .recording)
        #expect(recorder.copies[.drive] == .missing)
        try recorder.stopTake()
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
        try recorder.stopTake()
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
        try recorder.stopTake()
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
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(recorder.copies[.drive] == .complete)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        #expect(recorder.copies[.drive] == .recording)
        try recorder.stopTake()
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

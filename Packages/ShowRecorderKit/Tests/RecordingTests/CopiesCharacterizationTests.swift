import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

/// What the Recorder tells the screens about the Copies of a Take, before, during and after it: the running words
/// (`copyStatus`), the ended words (`lastTakeOutcomes`) and whether Repair is running. Pinned as they are today
/// (#550), so moving the readers to one "Copies of a Take" answer can't change what they see.
extension GapTests {
    struct Bridge: Equatable, CustomStringConvertible {
        var recording: Bool
        var device: CopyStatus
        var drive: CopyStatus
        var outcomes: [DestinationKind: CopyOutcome]
        var repairing: Bool

        var description: String {
            "recording \(recording), device \(device), drive \(drive), outcomes \(outcomes.sorted { $0.key.rawValue < $1.key.rawValue }), repairing \(repairing)"
        }
    }

    func bridge(_ recorder: Recorder) -> Bridge {
        Bridge(recording: recorder.isRecording, device: recorder.copyStatus(.device), drive: recorder.copyStatus(.drive),
               outcomes: recorder.lastTakeOutcomes, repairing: recorder.isRepairing)
    }

    @Test("Characterization (#550): two healthy Copies, idle, during and after")
    func characterizeTwoCopies() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [])
        try recorder.arm(audio)
        #expect(bridge(recorder) == Bridge(recording: false, device: .missing, drive: .missing, outcomes: [:], repairing: false))

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        #expect(bridge(recorder) == Bridge(recording: true, device: .recording, drive: .recording, outcomes: [:], repairing: false))

        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(bridge(recorder) == Bridge(recording: false, device: .recording, drive: .recording,
                                           outcomes: [.device: .complete, .drive: .complete], repairing: false))
    }

    @Test("Characterization (#550): no Drive at record")
    func characterizeNoDrive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        #expect(bridge(recorder) == Bridge(recording: true, device: .recording, drive: .missing, outcomes: [:], repairing: false))

        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(bridge(recorder) == Bridge(recording: false, device: .recording, drive: .missing,
                                           outcomes: [.device: .complete], repairing: false))
    }

    @Test("Characterization (#550): the Drive fails and comes back; Repair fills its Gap")
    func characterizeDriveBack() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }
        #expect(bridge(recorder) == Bridge(recording: true, device: .recording, drive: .interrupted, outcomes: [:], repairing: false))

        // The Drive rejoins once its writer has finished; ask until it has.
        try await waitUntil {
            recorder.checkDestinations()
            return recorder.copyStatus(.drive) == .recording
        }
        #expect(bridge(recorder) == Bridge(recording: true, device: .recording, drive: .recording, outcomes: [:], repairing: false))

        try await deliverBlocks(5, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(bridge(recorder) == Bridge(recording: false, device: .recording, drive: .recording,
                                           outcomes: [.device: .complete, .drive: .repaired], repairing: false))
    }

    @Test("Characterization (#550): the Drive fails and never comes back; Repair fills it at stop")
    func characterizeDriveGone() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(bridge(recorder) == Bridge(recording: false, device: .recording, drive: .interrupted,
                                           outcomes: [.device: .complete, .drive: .repaired], repairing: false))
    }

    @Test("Characterization (#550): the Device runs short of space; its Copy retires and reads as interrupted")
    func characterizeDeviceRetired() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let free = FreeSpace(device: 100_000_000, drive: 100_000_000)
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
                                freeSpace: { free.bytes(at: $0) }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(4, to: audio, recorder, sample: counting())
        free.device = 5_000_000
        recorder.checkDestinations()
        #expect(bridge(recorder) == Bridge(recording: true, device: .interrupted, drive: .recording, outcomes: [:], repairing: false))

        try await deliverBlocks(2, to: audio, recorder, sample: counting())   // the Take goes on without the Device
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(bridge(recorder) == Bridge(recording: false, device: .interrupted, drive: .recording,
                                           outcomes: [.device: .hasGaps, .drive: .complete], repairing: false))
    }

    @Test("Characterization (#550): the Device fails mid-Take (not for space); the Drive carries on")
    func characterizeDeviceFails() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.device])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copyStatus(.device) == .interrupted }
        #expect(bridge(recorder) == Bridge(recording: true, device: .interrupted, drive: .recording, outcomes: [:], repairing: false))

        try recorder.stopTake()
        await recorder.waitForRepair()
        // A failed Copy is Repaired from the other; one retired for space (above) keeps its Gap.
        #expect(bridge(recorder) == Bridge(recording: false, device: .interrupted, drive: .recording,
                                           outcomes: [.device: .repaired, .drive: .complete], repairing: false))
    }

    @Test("Characterization (#550): both Copies fail, so the Take ends on its own")
    func characterizeBothFail() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.device, .drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        try await waitUntil { !recorder.isRecording }
        await recorder.waitForRepair()
        #expect(bridge(recorder) == Bridge(recording: false, device: .interrupted, drive: .interrupted,
                                           outcomes: [.device: .repairFailed, .drive: .repairFailed], repairing: false))
    }

    @Test("Characterization (#550): a Drive that joins mid-Take")
    func characterizeDriveJoins() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let available = DriveSwitch()
        let recorder = Recorder(deviceFolder: device, driveFolder: { available.folder.map { DriveAccess(folder: $0) } },
                                now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        #expect(bridge(recorder) == Bridge(recording: true, device: .recording, drive: .missing, outcomes: [:], repairing: false))
        available.folder = drive
        recorder.checkDestinations()
        #expect(bridge(recorder) == Bridge(recording: true, device: .recording, drive: .recording, outcomes: [:], repairing: false))

        try await deliverBlocks(5, from: 4_800, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(bridge(recorder) == Bridge(recording: false, device: .recording, drive: .recording,
                                           outcomes: [.device: .complete, .drive: .repaired], repairing: false))
    }

    @Test("Characterization (#550): a second Take starts; the last Take's outcomes are still there while it runs")
    func characterizeSecondTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()
        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        // The running words are the new Take's; the ended words are still the last Take's (the screens show them only
        // when no Take is running).
        #expect(bridge(recorder) == Bridge(recording: true, device: .recording, drive: .recording,
                                           outcomes: [.device: .complete, .drive: .complete], repairing: false))
        try recorder.stopTake()
        await recorder.waitForRepair()
    }
}

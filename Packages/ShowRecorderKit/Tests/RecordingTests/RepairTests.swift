import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Testing

extension GapTests {
    /// Every file in the Take folder of `copy`, name → bytes.
    func takeFiles(in copy: URL) throws -> [String: Data] {
        let folder = copy.appending(path: "2026-10-06 Show/Take 01")
        return try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: folder.path).map {
            ($0, try Data(contentsOf: folder.appending(path: $0)))
        })
    }

    @Test("After a Drive fails and comes back, Repair fills the Gap and both Copies end byte-identical")
    func repairMakesCopiesIdenticalAfterDriveReturns() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder)
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }
        recorder.checkDestinations()
        try await deliverBlocks(5, to: audio, recorder)
        try recorder.stopTake()
        await recorder.waitForRepair()

        let deviceFiles = try takeFiles(in: device)
        let driveFiles = try takeFiles(in: drive)
        #expect(deviceFiles.keys.sorted() == driveFiles.keys.sorted())
        for (name, data) in deviceFiles {
            #expect(driveFiles[name] == data, "\(name) differs between the Copies")
        }
        let take = try decodedTake(device)
        #expect(take.repairs == [.init(copy: .drive, start: 480, end: 4800, outcome: .repaired)])
        #expect(recorder.lastTakeOutcomes[.device] == .complete)
        #expect(recorder.lastTakeOutcomes[.drive] == .repaired)

        for copy in [device, drive] {
            let report = try String(contentsOf: copy.appending(path: "2026-10-06 Show/Report.html"), encoding: .utf8)
            #expect(report.contains("<th>Result</th>"))
            #expect(report.contains("<td>Repaired</td>"), "the Gap's result in \(copy.lastPathComponent)'s report")
        }
    }

    @Test("A Drive that never came back is repaired at stop, from the Device")
    func repairFillsTrailingGap() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let recorder = recorder(failing: [.drive])
        try recorder.arm(audio)

        try recorder.startTake()
        for block in 0..<10 {
            audio.deliver((0..<2).map { channel in (0..<480).map { RecordingTakeTests.sample(Int32(channel * 100_000 + block * 480 + $0)) } })
            try await waitUntil { recorder.bufferedFrameCount == 0 }
        }
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }
        try recorder.stopTake()
        await recorder.waitForRepair()

        let deviceFiles = try takeFiles(in: device)
        let driveFiles = try takeFiles(in: drive)
        for (name, data) in deviceFiles { #expect(driveFiles[name] == data, "\(name) differs between the Copies") }
        #expect(try StemFile(contentsOf: drive.appending(path: "2026-10-06 Show/Take 01/02 USB 02.wav")).samples.count == 4800)
        #expect(recorder.lastTakeOutcomes[.drive] == .repaired)
    }

    @Test("A Drive that joined late is repaired from the Device")
    func repairFillsJoinGap() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let available = DriveSwitch()
        let recorder = Recorder(deviceFolder: device, driveFolder: { available.folder.map { DestinationAccess(folder: $0) } }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder)
        recorder.addMarker(named: "Verse")
        available.folder = drive
        recorder.checkDestinations()
        try await deliverBlocks(5, to: audio, recorder)
        try recorder.stopTake()
        await recorder.waitForRepair()

        let deviceFiles = try takeFiles(in: device)
        let driveFiles = try takeFiles(in: drive)
        for (name, data) in deviceFiles { #expect(driveFiles[name] == data, "\(name) differs between the Copies") }
        #expect(recorder.lastTakeOutcomes[.drive] == .repaired)
    }

    @Test("A stretch both Copies are missing stays silence and is reported as Repair failed")
    func repairFailsWhereBothCopiesAreMissing() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.device, .drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder)
        try await waitUntil { !recorder.isRecording }
        await recorder.waitForRepair()

        #expect(recorder.lastTakeOutcomes[.device] == .repairFailed)
        #expect(recorder.lastTakeOutcomes[.drive] == .repairFailed)
        #expect(try decodedTake(device).repairs.allSatisfy { $0.outcome == .failed })
    }

    @Test("A Take with no Gaps has two complete Copies and nothing to repair")
    func noGapsMeansComplete() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder)
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(recorder.lastTakeOutcomes == [.device: .complete, .drive: .complete])
        #expect(try decodedTake(device).repairs.isEmpty)
    }

    @Test("Repair doesn't fill a Destination that was stopped for being nearly full")
    func repairKeepsTheSpaceReserve() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let free = FreeSpace(device: 100_000_000, drive: 100_000_000)
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { DestinationAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            freeSpace: { free.bytes(at: $0) })
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(4, to: audio, recorder)
        free.device = 5_000_000  // under the 60 s reserve: the Device Copy stops here
        recorder.checkDestinations()
        try await deliverBlocks(2, to: audio, recorder)
        try recorder.stopTake()
        await recorder.waitForRepair()

        let take = "2026-10-06 Show/Take 01"
        #expect(try StemFile(contentsOf: device.appending(path: "\(take)/01 USB 01.wav")).samples.count == 4 * 480)
        #expect(recorder.lastTakeOutcomes[.device] == .hasGaps)
    }

    @Test("The last Take's outcome isn't overwritten by an earlier Take's Repair finishing late")
    func laterTakeOutcomeWins() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder)
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }
        try recorder.stopTake()  // Take 1 has a Gap: Repair starts
        try recorder.startTake()
        audio.deliver([[0]])
        try recorder.stopTake()  // Take 2 is complete, before Take 1's Repair gets to run
        await recorder.waitForRepair()

        #expect(recorder.lastTakeOutcomes == [.device: .complete, .drive: .complete])
        #expect(!recorder.isRepairing)
    }
}

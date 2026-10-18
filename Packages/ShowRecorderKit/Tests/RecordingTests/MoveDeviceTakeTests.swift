import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#630): a Drive only Take the Device holds whole moves to the Drive once the Drive is there.
extension DriveOnlyTakeTests {
    /// Whether the Drive is connected, switched by the test.
    final class DriveSwitch: @unchecked Sendable {
        var connected = false
    }

    /// A Drive only recorder whose Drive is there only while `drive.connected`.
    func recorder(drive switched: DriveSwitch) -> Recorder {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { switched.connected ? DriveAccess(folder: drive) : nil }, now: { RecordingTakeTests.showDay },
            destinationCheckInterval: nil)
        recorder.recordTo = .drive
        return recorder
    }

    /// Records a 4 800-frame Drive only Take with no Drive, then connects the Drive.
    func recordDeviceOnlyTake(_ switched: DriveSwitch) async throws -> Recorder {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(drive: switched)
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        switched.connected = true
        return recorder
    }

    @Test("A Drive only Take recorded with no Drive moves to the Drive once it is there, and leaves the Device (#630)")
    func moveDeviceOnlyTake() async throws {
        let switched = DriveSwitch()
        let recorder = try await recordDeviceOnlyTake(switched)

        let results = await recorder.moveDriveOnlyTakes()

        #expect(results == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(try driveSamples(frames: 4_800) == (0..<4_800).map { counting()($0, 0) }, "the Drive has the whole Take")
        let onDrive = try TakeMetadata.read(fromTakeFolder: drive.appending(path: take))
        #expect(onDrive.gaps == [.init(copy: .drive, start: 0, end: 4_800)])
        #expect(onDrive.outcome(ofCopy: .drive) == .repaired)
        #expect(onDrive.driveOnly == true)
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "2026-10-06 Show/Show.json").path), "the Drive's Show is described")
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "the Device's Take is gone")
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/.moved Take 01").path))
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/Show.json").path), "the Device keeps its Show")
        #expect(recorder.copies[.device] == .moved)
        #expect(recorder.copies[.drive] == .repaired)
    }

    /// A Drive only Take started with no Drive, which the Drive joins at frame 4 800 for the rest; Repair at Stop fills
    /// the Drive's lead from the Device, which keeps its whole Copy.
    func recordJoinMidTake() async throws -> Recorder {
        let switched = DriveSwitch()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(drive: switched)
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        switched.connected = true
        await recorder.checkDestinations()
        try await deliverBlocks(10, from: 4_800, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).outcome(ofCopy: .drive) == .repaired)
        #expect(try StemWriter.readSamples(url: device.appending(path: "\(take)/01 USB 01.wav"), frames: 0..<9_600) == (0..<9_600).map { counting()($0, 0) })
        return recorder
    }

    @Test("A Drive only Take the Drive joined mid-Take leaves the Device once the Drive is checked whole (#630)")
    func moveJoinMidTake() async throws {
        let recorder = try await recordJoinMidTake()

        let results = await recorder.moveDriveOnlyTakes()

        #expect(results == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(try driveSamples(frames: 9_600) == (0..<9_600).map { counting()($0, 0) })
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path))
    }

    @Test("A Drive the Drive joined mid-Take that differs from the Device keeps the Device's Take untouched (#630)")
    func joinMidTakeDifferentAudio() async throws {
        let recorder = try await recordJoinMidTake()
        // The Drive's lead isn't what the Device holds, though its Take.json says it is Repaired.
        let stem = drive.appending(path: "\(take)/01 USB 01.wav")
        let handle = try FileHandle(forWritingTo: stem)
        try handle.seek(toOffset: UInt64(StemWriter.dataStart))
        try handle.write(contentsOf: Data(count: 480 * StemWriter.bytesPerSample))
        try handle.close()
        let deviceStem = device.appending(path: "\(take)/01 USB 01.wav")
        let before = try Data(contentsOf: deviceStem)

        let results = await recorder.moveDriveOnlyTakes()

        guard case .kept(let reasons) = try #require(results.first?.outcome) else { Issue.record("\(results)"); return }
        #expect(reasons.contains { $0.contains("different audio") }, "\(reasons)")
        #expect(try Data(contentsOf: deviceStem) == before, "the Device's Take is untouched")
    }

    @Test("Beside a Take with two Copies, only the Drive only Take moves; the other's Device folder is untouched (#630)")
    func onlyDriveOnlyTakesMove() async throws {
        let switched = DriveSwitch()
        switched.connected = true
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(drive: switched)
        recorder.recordTo = .both
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        switched.connected = false
        recorder.recordTo = .drive
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        switched.connected = true
        let twoCopies = device.appending(path: take)
        let before = try FileManager.default.contentsOfDirectory(atPath: twoCopies.path).sorted()
        let stem = try Data(contentsOf: twoCopies.appending(path: "01 USB 01.wav"))

        let results = await recorder.moveDriveOnlyTakes()

        #expect(results == [.init(show: "2026-10-06 Show", take: 2, outcome: .moved)])
        #expect(try FileManager.default.contentsOfDirectory(atPath: twoCopies.path).sorted() == before)
        #expect(try Data(contentsOf: twoCopies.appending(path: "01 USB 01.wav")) == stem)
    }

    @Test("A move cut off after setting the Device's Take aside is finished by the next move with the Drive, not without it (#630)")
    func nextMoveFinishesACutOffMove() async throws {
        let switched = DriveSwitch()
        let recorder = try await recordDeviceOnlyTake(switched)
        #expect(await recorder.moveDriveOnlyTakes().map(\.outcome) == [.moved])
        // As a crash leaves it: the Take set aside on the Device, not yet deleted.
        let setAside = device.appending(path: "2026-10-06 Show/.moved Take 01")
        try FileManager.default.copyItem(at: drive.appending(path: take), to: setAside)
        switched.connected = false

        #expect(await recorder.moveDriveOnlyTakes().isEmpty, "nothing without the Drive")
        #expect(FileManager.default.fileExists(atPath: setAside.path))

        switched.connected = true
        let results = await recorder.moveDriveOnlyTakes()

        #expect(results == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(!FileManager.default.fileExists(atPath: setAside.path))
    }

    @Test("A Drive the Drive joined mid-Take whose Repair at Stop didn't run is filled from the Device and the Device's Take removed (#630)")
    func joinMidTakeUnrepaired() async throws {
        let recorder = try await recordJoinMidTake()
        // As if Repair at Stop had been skipped: the Drive's lead is still silence and its Gap unrepaired.
        var onDrive = try TakeMetadata.read(fromTakeFolder: drive.appending(path: take))
        onDrive.repairs = []
        try onDrive.write(to: drive.appending(path: take))
        let stem = drive.appending(path: "\(take)/01 USB 01.wav")
        let handle = try FileHandle(forWritingTo: stem)
        try handle.seek(toOffset: UInt64(StemWriter.dataStart))
        try handle.write(contentsOf: Data(count: 4_800 * StemWriter.bytesPerSample))
        try handle.close()

        let results = await recorder.moveDriveOnlyTakes()

        #expect(results == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(try driveSamples(frames: 9_600) == (0..<9_600).map { counting()($0, 0) })
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path))
    }
}

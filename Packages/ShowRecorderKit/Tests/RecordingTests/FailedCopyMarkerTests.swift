import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// A Drive Copy whose write failed is marked in Take.json like one Stop gave up on, so the next time the Drive is seen,
/// recovery reads what its Stems really hold and records any shortfall below the committed count as a Gap (#854).
/// Like a Copy Stop gave up on, recovery trusts the file's length (`CutOffTake.finishStem`), not only the last header commit.
@MainActor
@Suite("Failed Drive Copy marker")
struct FailedCopyMarkerTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "FailedCopyMarkerTests-\(UUID().uuidString)")
    let show = "2026-10-06 Show"
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    /// A Take of 4,800 frames whose Drive Stem (or, with `failing: .device`, the Device's) fails after 480.
    private func recordTakeWithFailingDrive(failing: DestinationKind = .drive) async throws {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                return url.path.hasPrefix(drive.path) == (failing == .drive) ? FailingStem(writer, healthyFrames: 480) : writer
            },
            destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await Task.sleep(for: .milliseconds(100))
        try await recorder.stopTake()
        await recorder.waitForRepair()
    }

    @Test("A Drive Copy whose write failed is marked in the Device's Take.json")
    func failedCopyIsMarked() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await recordTakeWithFailingDrive()
        #expect(try TakeMetadata.read(fromTakeFolder: device.appending(path: "\(show)/Take 01")).abandonedCopies == [.drive])
    }

    @Test("When the Drive is seen again with a Stem shorter than the committed count, the Gap starts at the file's real end")
    func recoveryClosesTheShortfall() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await recordTakeWithFailingDrive()
        let driveTake = drive.appending(path: "\(show)/Take 01")
        let stem = driveTake.appending(path: try TakeMetadata.read(fromTakeFolder: driveTake).usbChannels[0].stemFile)
        let before = try StemFile.inspect(stem).framesOnDisk
        // The Drive's own cache never reached the medium: the file ends before what was committed.
        let handle = try FileHandle(forWritingTo: stem)
        try handle.truncate(atOffset: try handle.seekToEnd() - 600)
        try handle.close()
        let real = try StemFile.inspect(stem).framesOnDisk
        #expect(real < before)

        _ = AbandonedCopyRecovery.finish(deviceShow: device.appending(path: show), driveShow: drive.appending(path: show))

        let metadata = try TakeMetadata.read(fromTakeFolder: device.appending(path: "\(show)/Take 01"))
        #expect(metadata.abandonedCopies == nil)
        #expect(!metadata.repairs.contains { $0.copy == .drive }, "a repair of a Stem that turned out short is stale")
        #expect(metadata.gaps.contains { $0.copy == .drive && $0.start == Int(real) }, "the Gap starts at the real end: \(metadata.gaps)")
    }

    @Test("A Device Copy that failed isn't marked, and a Take that finished normally has no marker")
    func onlyAFailedDriveIsMarked() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await recordTakeWithFailingDrive(failing: .device)
        #expect(try TakeMetadata.read(fromTakeFolder: device.appending(path: "\(show)/Take 01")).abandonedCopies == nil)
    }

    @Test("A Stem that isn't shorter than the committed count: recovery clears the marker and leaves the Drive's Gaps as they were")
    func nothingMissingChangesNothing() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await recordTakeWithFailingDrive()
        let take = device.appending(path: "\(show)/Take 01")
        let gapsBefore = try TakeMetadata.read(fromTakeFolder: take).gaps.filter { $0.copy == .drive }

        _ = AbandonedCopyRecovery.finish(deviceShow: device.appending(path: show), driveShow: drive.appending(path: show))

        let after = try TakeMetadata.read(fromTakeFolder: take)
        #expect(after.abandonedCopies == nil)
        #expect(after.repairs.contains { $0.copy == .drive }, "what Repair did stays on the record")
        #expect(after.gaps.filter { $0.copy == .drive } == gapsBefore, "\(gapsBefore) -> \(after.gaps)")
    }
}

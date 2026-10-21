import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
@testable import TakeFile
import Testing

private extension StemWriter {
    func append(_ samples: [Float]) throws { try samples.withUnsafeBufferPointer { try append($0) } }
}

/// A Drive Copy Stop gave up on is finished when its Drive is back (#817): its Stems cover the audio on disk, its Gaps
/// are worked out again, and the marker is cleared.
@MainActor
@Suite("Abandoned Copy recovery")
struct AbandonedCopyRecoveryTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "AbandonedCopyRecoveryTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let show = "2026-10-06 Show"
    var deviceTake: URL { device.appending(path: "\(show)/Take 01") }
    var driveTake: URL { drive.appending(path: "\(show)/Take 01") }

    /// A finished 480-frame Take on both Copies; then the Drive's Stems are replaced by what an abandoned Copy leaves:
    /// 240 frames on disk and a header that says 0. The Device's Take.json marks the Drive abandoned, with a Gap for
    /// the whole Take as Stop recorded it (the header-committed length was 0).
    func abandonedTake(channels: Int = 1) async throws -> TakeMetadata {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: channels)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver(Array(repeating: Array(repeating: Float(0.2), count: 480), count: channels))
        try await recorder.stopTake()
        await recorder.waitForRepair()
        recorder.disarm()
        var metadata = try TakeMetadata.read(fromTakeFolder: deviceTake)
        let info = StemWriter.Info(
            sampleRate: 48_000, description: "", originator: "ShowRecorder", timeReference: metadata.timeReference,
            originationDate: metadata.startedAt)
        for channel in metadata.usbChannels {
            let url = driveTake.appending(path: channel.stemFile)
            try FileManager.default.removeItem(at: url)
            let writer = try StemWriter.open(url: url, info: info, resumingAt: nil)
            try writer.commitHeader()
            try writer.append(Array(repeating: 0.2, count: 240))
        }
        metadata.abandonedCopies = [.drive]
        metadata.gaps = [TakeMetadata.Gap(copy: .drive, start: 0, end: 480)]
        try metadata.write(to: deviceTake)
        return metadata
    }

    @Test("A marked Drive Copy's Stems are finished to the audio on disk, its Gap is everything past what Stop confirmed, and the marker is cleared")
    func finishesTheMarkedCopy() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try await abandonedTake()
        let found = finishNow()
        #expect(found.count == 1)
        let metadata = try #require(found.first?.metadata)
        #expect(metadata.abandonedCopies == nil)
        #expect(metadata.gaps == [TakeMetadata.Gap(copy: .drive, start: 0, end: 480)])
        #expect(found.first?.folders[.drive]?.path == driveTake.path && found.first?.folders[.device]?.path == deviceTake.path)
        for channel in original.usbChannels {
            #expect(try StemFile.inspect(driveTake.appending(path: channel.stemFile)).frameCount == 240)
        }
        for folder in [deviceTake, driveTake] {
            let written = try TakeMetadata.read(fromTakeFolder: folder)
            #expect(written.abandonedCopies == nil)
            #expect(written.gaps == [TakeMetadata.Gap(copy: .drive, start: 0, end: 480)])
        }
        // Done once: the marker is gone, so a second look finds nothing.
        #expect(finishNow().isEmpty)
    }

    @Test("The Recorder finishes the marked Copy when the Drive is back, and Repair fills the tail from the Device")
    func recorderRecovers() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try await abandonedTake()
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        await recorder.recoverAbandonedCopies()
        await recorder.waitForRepair()
        for channel in original.usbChannels {
            #expect(try StemFile.inspect(driveTake.appending(path: channel.stemFile)).frameCount == 480)
        }
        let metadata = try TakeMetadata.read(fromTakeFolder: deviceTake)
        #expect(metadata.abandonedCopies == nil)
        #expect(metadata.outcome(ofCopy: .drive) == .repaired)
        #expect(recorder.copies[.drive] == .repaired)
    }

    @Test("With no Drive reachable the marker stays, and nothing happens")
    func noDriveNoChange() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await abandonedTake()
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay })
        await recorder.recoverAbandonedCopies()
        #expect(try TakeMetadata.read(fromTakeFolder: deviceTake).abandonedCopies == [.drive])
    }

    private func finishNow(skipping: Set<Int> = []) -> [CutOffTake.Found] {
        AbandonedCopyRecovery.finish(deviceShow: device.appending(path: show), driveShow: drive.appending(path: show), skipping: skipping)
    }

    @Test("A Gap that straddles what the Drive has is clipped to it, not dropped; the tail Stop recorded is replaced")
    func straddlingGapIsClipped() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = try await abandonedTake()
        // Stop confirmed 240 frames (the last header commit), so its tail starts there.
        metadata.gaps = [.init(copy: .drive, start: 100, end: 400), .init(copy: .drive, start: 240, end: 480)]
        try metadata.write(to: deviceTake)
        let gaps = try #require(finishNow().first).metadata.gaps
        #expect(gaps.sorted { $0.start < $1.start } == [.init(copy: .drive, start: 100, end: 240), .init(copy: .drive, start: 240, end: 480)])
    }

    @Test("A Drive only Take's tail comes from its stand-ins when the Device has no Stems at the Take's root")
    func driveOnlyTail() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = try await abandonedTake()
        for channel in metadata.usbChannels { try FileManager.default.removeItem(at: deviceTake.appending(path: channel.stemFile)) }
        metadata.standIns = [.init(start: 240, end: 480)]
        metadata.gaps = [.init(copy: .drive, start: 240, end: 480)]
        try metadata.write(to: deviceTake)
        let gaps = try #require(finishNow().first).metadata.gaps
        #expect(gaps == [.init(copy: .drive, start: 240, end: 480)])
    }

    @Test("A file longer than what Stop confirmed: the tail starts at the confirmed length, not at the file's end (torn bytes past the commit)")
    func tailLongerThanTheCommit() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = try await abandonedTake()   // 240 frames on disk, 480 in the Take
        metadata.gaps = [.init(copy: .drive, start: 100, end: 120), .init(copy: .drive, start: 200, end: 480)]   // Stop confirmed 200
        try metadata.write(to: deviceTake)
        let gaps = try #require(finishNow().first).metadata.gaps
        #expect(gaps.sorted { $0.start < $1.start } == [.init(copy: .drive, start: 100, end: 120), .init(copy: .drive, start: 200, end: 480)])
    }

    @Test("A recorded tail that stops short of the Take's end (the Device is longer than Stop knew) is still the tail")
    func tailEndingBeforeTheTakeEnd() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = try await abandonedTake()   // 240 frames on disk, 480 on the Device
        metadata.gaps = [.init(copy: .drive, start: 200, end: 400)]   // Stop confirmed 200 and knew of 400 frames
        try metadata.write(to: deviceTake)
        #expect(try #require(finishNow().first).metadata.gaps == [.init(copy: .drive, start: 200, end: 480)])
    }

    @Test("A file shorter than what Stop confirmed: the tail starts at the file's real end")
    func tailShorterThanTheCommit() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = try await abandonedTake()   // 240 frames on disk
        metadata.gaps = [.init(copy: .drive, start: 400, end: 480)]   // Stop thought 400 were durable
        try metadata.write(to: deviceTake)
        #expect(try #require(finishNow().first).metadata.gaps == [.init(copy: .drive, start: 240, end: 480)])
    }

    @Test("A Drive whose Take.json is another Take's, or with a Stem that can't be read, is not touched and the marker stays")
    func wrongDriveOrUnreadableStem() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try await abandonedTake(channels: 2)
        // One Stem missing on the Drive.
        let missing = driveTake.appending(path: original.usbChannels[1].stemFile)
        let hidden = root.appending(path: "hidden.wav")
        try FileManager.default.moveItem(at: missing, to: hidden)
        #expect(finishNow().isEmpty)
        #expect(try TakeMetadata.read(fromTakeFolder: deviceTake).abandonedCopies == [.drive])
        try FileManager.default.moveItem(at: hidden, to: missing)
        // Another Take's Take.json on the Drive: a different Drive with the same Show and Take number.
        var other = original
        other.startedAt = original.startedAt.addingTimeInterval(86_400)
        try other.write(to: driveTake)
        #expect(finishNow().isEmpty)
        #expect(try TakeMetadata.read(fromTakeFolder: deviceTake).abandonedCopies == [.drive])
    }

    @Test("A Take this launch abandoned is skipped: its writer may still be alive and writing")
    func skipsTakesAbandonedThisLaunch() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await abandonedTake()
        #expect(finishNow(skipping: [1]).isEmpty)
        #expect(try TakeMetadata.read(fromTakeFolder: deviceTake).abandonedCopies == [.drive])
        #expect(finishNow().count == 1)
    }

    /// Two finished 480-frame Takes on both Copies, with Take `marked`'s Drive Copy as an abandoned Copy leaves it.
    func twoTakes(marked: [Int]) async throws {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let drive = drive
        let first = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try first.arm(audio)
        for _ in 1...2 {
            try first.startTake()
            audio.deliver([Array(repeating: 0.2, count: 480)])
            try await first.stopTake()
            await first.waitForRepair()
        }
        first.disarm()
        for take in marked {
            let name = TakeMetadata.name(take: take)
            let deviceFolder = device.appending(path: "\(show)/\(name)"), driveFolder = drive.appending(path: "\(show)/\(name)")
            var metadata = try TakeMetadata.read(fromTakeFolder: deviceFolder)
            let info = StemWriter.Info(
                sampleRate: 48_000, description: "", originator: "ShowRecorder", timeReference: metadata.timeReference,
                originationDate: metadata.startedAt)
            for channel in metadata.usbChannels {
                let url = driveFolder.appending(path: channel.stemFile)
                try FileManager.default.removeItem(at: url)
                let writer = try StemWriter.open(url: url, info: info, resumingAt: nil)
                try writer.commitHeader()
                try writer.append(Array(repeating: 0.2, count: 240))
            }
            metadata.abandonedCopies = [.drive]
            metadata.gaps = [TakeMetadata.Gap(copy: .drive, start: 0, end: 480)]
            try metadata.write(to: deviceFolder)
        }
    }

    func driveStemFrames(take: Int) throws -> UInt64 {
        let metadata = try TakeMetadata.read(fromTakeFolder: device.appending(path: "\(show)/\(TakeMetadata.name(take: take))"))
        let folder = drive.appending(path: "\(show)/\(TakeMetadata.name(take: take))")
        return try StemFile.inspect(folder.appending(path: metadata.usbChannels[0].stemFile)).frameCount
    }

    @Test("An earlier marked Take is finished and Repaired too, without taking the last Take's place on the screen")
    func earlierTakeIsRepaired() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await twoTakes(marked: [1])
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let before = recorder.copies[.drive]
        await recorder.recoverAbandonedCopies()
        await recorder.waitForRepair()
        #expect(try driveStemFrames(take: 1) == 480)
        #expect(try TakeMetadata.read(fromTakeFolder: deviceTake).outcome(ofCopy: .drive) == .repaired)
        #expect(recorder.copies[.drive] == before, "Take 1's Repair is not the last Take's")
    }

    @Test("With the last Take marked too, both are Repaired and the screen shows the last one's result")
    func bothTakesRepaired() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await twoTakes(marked: [1, 2])
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        await recorder.recoverAbandonedCopies()
        await recorder.waitForRepair()
        #expect(try driveStemFrames(take: 1) == 480)
        #expect(try driveStemFrames(take: 2) == 480)
        #expect(recorder.copies[.drive] == .repaired)
    }

    @Test("A Drive only Take whose Device folder is gone is found on the Drive: its Stems are finished and the marker cleared")
    func driveOnlyWithNoDeviceFolder() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try await abandonedTake()
        // Stop removed the Device's empty Take folder; the marker reached only the Drive's Take.json.
        try original.write(to: driveTake)
        try FileManager.default.removeItem(at: deviceTake)
        let found = try #require(finishNow().first)
        #expect(found.folders.count == 1 && found.folders[.drive]?.path == driveTake.path)
        #expect(found.metadata.gaps == [TakeMetadata.Gap(copy: .drive, start: 0, end: 480)])
        for channel in original.usbChannels {
            #expect(try StemFile.inspect(driveTake.appending(path: channel.stemFile)).frameCount == 240)
        }
        #expect(try TakeMetadata.read(fromTakeFolder: driveTake).abandonedCopies == nil)
        #expect(finishNow().isEmpty)
    }

    @Test("A Take found only on the Drive is ignored above the Show's Take count, with no recorded tail, or when its Device Take.json is corrupt")
    func driveOnlyGuards() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try await abandonedTake()
        // A Device Take.json that is there but can't be read is not replaced by the Drive's.
        try original.write(to: driveTake)
        try Data("{".utf8).write(to: deviceTake.appending(path: TakeMetadata.fileName))
        #expect(finishNow().isEmpty)
        try FileManager.default.removeItem(at: deviceTake)
        // Above the Show's Take count: another session's Take on a Drive with the same Show name.
        #expect(AbandonedCopyRecovery.finish(deviceShow: device.appending(path: show), driveShow: drive.appending(path: show), upTo: 0).isEmpty)
        // No tail recorded and no Device: the Take can't be told short, so the marker stays.
        var noTail = original
        noTail.gaps = []
        try noTail.write(to: driveTake)
        #expect(finishNow().isEmpty)
        #expect(try TakeMetadata.read(fromTakeFolder: driveTake).abandonedCopies == [.drive])
    }

    @Test("A Take with no marker, or whose Drive Take folder isn't there, is left alone")
    func leavesOthersAlone() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await abandonedTake()
        var metadata = try TakeMetadata.read(fromTakeFolder: deviceTake)
        // Not this Drive: its Take folder is missing.
        try FileManager.default.moveItem(at: driveTake, to: root.appending(path: "elsewhere"))
        #expect(finishNow().isEmpty)
        #expect(try TakeMetadata.read(fromTakeFolder: deviceTake).abandonedCopies == [.drive], "the marker waits for its Drive")
        // No marker.
        try FileManager.default.moveItem(at: root.appending(path: "elsewhere"), to: driveTake)
        metadata.abandonedCopies = nil
        try metadata.write(to: deviceTake)
        #expect(finishNow().isEmpty)
    }
}

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

    @Test("A marked Drive Copy's Stems are finished to the audio on disk, its Gap is the missing tail, and the marker is cleared")
    func finishesTheMarkedCopy() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try await abandonedTake()
        let found = finishNow()
        #expect(found.count == 1)
        let metadata = try #require(found.first?.metadata)
        #expect(metadata.abandonedCopies == nil)
        #expect(metadata.gaps == [TakeMetadata.Gap(copy: .drive, start: 240, end: 480)])
        #expect(found.first?.folders[.drive]?.path == driveTake.path && found.first?.folders[.device]?.path == deviceTake.path)
        for channel in original.usbChannels {
            #expect(try StemFile.inspect(driveTake.appending(path: channel.stemFile)).frameCount == 240)
        }
        for folder in [deviceTake, driveTake] {
            let written = try TakeMetadata.read(fromTakeFolder: folder)
            #expect(written.abandonedCopies == nil)
            #expect(written.gaps == [TakeMetadata.Gap(copy: .drive, start: 240, end: 480)])
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
        metadata.gaps = [.init(copy: .drive, start: 100, end: 400), .init(copy: .drive, start: 0, end: 480)]
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
        try metadata.write(to: deviceTake)
        let gaps = try #require(finishNow().first).metadata.gaps
        #expect(gaps == [.init(copy: .drive, start: 240, end: 480)])
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

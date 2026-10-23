import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#656): the Recorder's side of deleting a kept Take by hand. Never during a Take or a save, never while a move
/// runs or a Device Copy Stop gave up on may still be written, and a deleted Take leaves the moves list.
@MainActor
@Suite("Recorder: deleting a kept Take from the Device")
struct RecorderReleaseTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "RecorderReleaseTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    var deviceTake: URL { device.appending(path: "2026-10-06 Show/Take 01") }
    var driveTake: URL { drive.appending(path: "2026-10-06 Show/Take 01") }
    static let startedAt = Date(timeIntervalSince1970: 1_791_331_200)

    func writeStem(_ url: URL, frames: Int, channel: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "Test", timeReference: 0, originationDate: Self.startedAt)
        let stem = try StemWriter(url: url, info: info)
        try (0..<frames).map { counting()($0, channel - 1) }.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    /// A crashed two-channel Take the Device holds at different lengths; the Drive holds both whole. The moves keep it.
    func makeKeptTake() throws {
        var metadata = TakeMetadata(
            show: "2026-10-06 Show", take: 1, startedAt: Self.startedAt, sampleRate: 48_000, timeReference: 0,
            usbChannels: (1...2).map { DeviceTakeReleaseTests.channel($0) })
        metadata.driveOnly = true
        for folder in [deviceTake, driveTake] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try metadata.write(to: deviceTake)
        try metadata.write(to: driveTake)
        for (index, frames) in [4_800, 3_000].enumerated() {
            try writeStem(deviceTake.appending(path: DeviceTakeReleaseTests.channel(index + 1).stemFile), frames: frames, channel: index + 1)
        }
        for channel in 1...2 { try writeStem(driveTake.appending(path: DeviceTakeReleaseTests.channel(channel).stemFile), frames: 4_800, channel: channel) }
    }

    func recorder(withDrive: Bool = true) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device, driveFolder: { withDrive ? DriveAccess(folder: drive) : nil }, now: { RecordingTakeTests.showDay },
            destinationCheckInterval: nil)
    }

    @Test("Asked, a kept Take the Drive holds everything of gives the facts for the confirmation, and nothing is deleted")
    func checkGivesTheFacts() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()

        guard case .ok(let summary) = await recorder().checkRelease(show: "2026-10-06 Show", take: 1) else { Issue.record("not ok"); return }
        #expect(summary.take == 1 && summary.channels == 2 && summary.stems == 2)
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("Delete removes the Take from the Device and from the moves list; the Drive's Copy stays")
    func releases() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        let recorder = recorder()
        await recorder.moveDriveOnlyTakes()
        #expect(recorder.moveReport.entries.map(\.status) == [.kept], "the moves keep it, with why")

        let outcome = await recorder.releaseFromDevice(show: "2026-10-06 Show", take: 1)

        #expect(outcome == .released)
        #expect(!FileManager.default.fileExists(atPath: deviceTake.path))
        #expect(FileManager.default.fileExists(atPath: driveTake.appending(path: "Take.json").path))
        #expect(recorder.moveReport.entries.isEmpty, "no longer listed as kept on the iPhone")
    }

    final class Ended: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    @Test("Each delete lets the Drive go exactly once, whether it deletes or keeps the Take, and leaves no move running (#890)")
    func driveLetGoOnce() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        let ended = Ended()
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive, stop: { ended.bump() }) },
            now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)

        // The Drive lacks a Stem: kept.
        let hidden = driveTake.appending(path: DeviceTakeReleaseTests.channel(2).stemFile)
        let aside = root.appending(path: "aside.wav")
        try FileManager.default.moveItem(at: hidden, to: aside)
        guard case .kept = await recorder.releaseFromDevice(show: "2026-10-06 Show", take: 1) else { Issue.record("not kept"); return }
        #expect(ended.count == 1, "kept")
        #expect(!recorder.isMoving)

        try FileManager.default.moveItem(at: aside, to: hidden)
        #expect(await recorder.releaseFromDevice(show: "2026-10-06 Show", take: 1) == .released)
        #expect(ended.count == 2, "released")
        #expect(!recorder.isMoving)
    }

    @Test("Not during a Take, and not during a save: the Take stays")
    func neverWhileABusyTake() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        let recorder = recorder()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()

        guard case .kept(let reasons) = await recorder.releaseFromDevice(show: "2026-10-06 Show", take: 1) else { Issue.record("not kept"); return }
        #expect(reasons.first?.contains("Take is running") == true)
        guard case .no = await recorder.checkRelease(show: "2026-10-06 Show", take: 1) else { Issue.record("check not refused"); return }
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
        try await recorder.stopTake()
    }

    @Test("Not while a Device Copy Stop gave up on may still be written")
    func notWhileTheDeviceMayStillBeWritten() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        let recorder = recorder()
        recorder.suspectCopies = [.device]

        guard case .kept = await recorder.releaseFromDevice(show: "2026-10-06 Show", take: 1) else { Issue.record("not kept"); return }
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("With no Drive connected nothing is deleted, and it says so")
    func needsTheDrive() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()

        guard case .kept(let reasons) = await recorder(withDrive: false).releaseFromDevice(show: "2026-10-06 Show", take: 1) else { Issue.record("not kept"); return }
        #expect(reasons.first?.contains("Drive") == true)
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A Show name that isn't a plain folder name, or a Take number below 1, deletes nothing")
    func refusesNamesThatEscape() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        // A twin Take outside the Shows folder, with a Drive twin that matches, as an escaping `show` would reach.
        let outside = root.appending(path: "Outside/Take 01")
        let outsideDrive = drive.appending(path: "Outside/Take 01")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDrive, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: deviceTake.appending(path: "Take.json"), to: outside.appending(path: "Take.json"))
        try FileManager.default.copyItem(at: driveTake.appending(path: "Take.json"), to: outsideDrive.appending(path: "Take.json"))
        let recorder = recorder()

        for show in ["../Outside", "..", ".", "", "A/B", ".hidden"] {
            guard case .kept = await recorder.releaseFromDevice(show: show, take: 1) else { Issue.record("\(show) not refused"); return }
            guard case .no = await recorder.checkRelease(show: show, take: 1) else { Issue.record("\(show) check not refused"); return }
        }
        guard case .kept = await recorder.releaseFromDevice(show: "2026-10-06 Show", take: 0) else { Issue.record("take 0 not refused"); return }
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }
}

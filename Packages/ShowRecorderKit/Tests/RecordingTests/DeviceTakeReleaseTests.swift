import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#656): the operator deletes a kept Take from this iPhone by hand, once the Drive verifiably holds everything
/// the Device holds of it. The delete sets the Device's Take aside, checks again against what is set aside, and only then
/// removes it, as the moves do.
@Suite("Deleting a kept Take from the Device")
struct DeviceTakeReleaseTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "DeviceTakeReleaseTests-\(UUID().uuidString)")
    var deviceShow: URL { root.appending(path: "Device/2026-10-06 Show") }
    var deviceTake: URL { deviceShow.appending(path: "Take 01") }
    var driveTake: URL { root.appending(path: "Drive/2026-10-06 Show/Take 01") }
    static let startedAt = Date(timeIntervalSince1970: 1_791_331_200)

    static func channel(_ number: Int) -> TakeMetadata.USBChannel {
        .init(usbChannel: number, stemFile: String(format: "%02d USB %02d.wav", number, number), source: .fallback(usbChannel: number))
    }

    func writeStem(_ url: URL, frames: Int, channel: Int, differs: Range<Int>? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "Test", timeReference: 0, originationDate: Self.startedAt)
        let stem = try StemWriter(url: url, info: info)
        try (0..<frames).map { differs?.contains($0) == true ? Float(0.5) : counting()($0, channel - 1) }
            .withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    /// A crashed Take of two channels the Device holds at different lengths; the Drive holds both whole.
    @discardableResult
    func make(deviceFrames: [Int] = [4_800, 3_000], driveFrames: [Int] = [4_800, 4_800]) throws -> TakeMetadata {
        var metadata = TakeMetadata(
            show: "2026-10-06 Show", take: 1, startedAt: Self.startedAt, sampleRate: 48_000, timeReference: 0,
            usbChannels: (1...deviceFrames.count).map(Self.channel))
        metadata.driveOnly = true
        for folder in [deviceTake, driveTake] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try metadata.write(to: deviceTake)
        try metadata.write(to: driveTake)
        for (index, frames) in deviceFrames.enumerated() { try writeStem(deviceTake.appending(path: Self.channel(index + 1).stemFile), frames: frames, channel: index + 1) }
        for (index, frames) in driveFrames.enumerated() { try writeStem(driveTake.appending(path: Self.channel(index + 1).stemFile), frames: frames, channel: index + 1) }
        return metadata
    }

    func driveBytes() throws -> [Data] {
        try FileManager.default.contentsOfDirectory(at: driveTake, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }.map { try Data(contentsOf: $0) }
    }

    func run(shouldStop: @escaping () -> Bool = { false }, at hook: @escaping (StandInMove.Step) -> Void = { _ in }) -> DeviceTakeRelease.Outcome {
        DeviceTakeRelease.run(deviceTake: deviceTake, driveTake: driveTake, shouldStop: shouldStop, at: hook)
    }

    @Test("A kept Take the Drive holds everything of is removed from the Device, and the Drive's Copy is not touched")
    func released() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try make()
        let before = try driveBytes()

        #expect(run() == .released)
        #expect(!FileManager.default.fileExists(atPath: deviceTake.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: deviceShow.path).filter { $0.hasPrefix(".moved") }.isEmpty, "no set-aside left")
        #expect(try driveBytes() == before, "the Drive's Take is byte for byte as it was")
    }

    @Test("A Drive that differs keeps the Device's Take, and says why")
    func differingDrive() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try make()
        try writeStem(driveTake.appending(path: Self.channel(1).stemFile), frames: 4_800, channel: 1, differs: 4_700..<4_701)

        guard case .kept(let reasons) = run() else { Issue.record("not kept"); return }
        #expect(reasons.first?.contains("channel 1") == true)
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: Self.channel(1).stemFile).path))
    }

    @Test("A Take the Device no longer has is nothing to do")
    func gone() {
        #expect(run() == .gone)
    }

    @Test("A Take started meanwhile stops it before anything is set aside")
    func stopped() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try make()

        #expect(run(shouldStop: { true }) == .stopped)
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A Drive that changes after the Device's Take is set aside puts the Take back")
    func secondCheckFailsPutsItBack() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try make()

        let outcome = run(at: { step in
            if step == .setAside {
                try? self.writeStem(self.driveTake.appending(path: Self.channel(2).stemFile), frames: 4_800, channel: 2, differs: 100..<101)
            }
        })

        guard case .kept = outcome else { Issue.record("not kept: \(outcome)"); return }
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path), "put back")
        #expect(try FileManager.default.contentsOfDirectory(atPath: deviceShow.path).filter { $0.hasPrefix(".moved") }.isEmpty)
    }

    @Test("A set-aside folder left by an earlier move keeps the Take")
    func setAsideInTheWay() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try make()
        try FileManager.default.createDirectory(at: deviceShow.appending(path: StandInMove.setAsideName(of: deviceTake)), withIntermediateDirectories: true)

        guard case .kept = run() else { Issue.record("not kept"); return }
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("The facts for the confirmation: which Take, how many Stems, and how long the Device's longest one is")
    func summary() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try make(deviceFrames: [48_000, 24_000], driveFrames: [48_000, 48_000])

        guard case .ok(let summary) = DeviceTakeRelease.check(deviceTake: deviceTake, driveTake: driveTake, shouldStop: { false }) else {
            Issue.record("not ok"); return
        }
        #expect(summary.take == 1)
        #expect(summary.channels == 2)
        #expect(summary.stems == 2)
        #expect(summary.longestSeconds == 1.0)
        #expect(summary.shortestSeconds == 0.5)
        #expect(FileManager.default.fileExists(atPath: deviceTake.path), "checking deletes nothing")
    }

    @Test("A check that fails gives the reasons and no summary")
    func checkFails() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try make(driveFrames: [100, 4_800])

        guard case .no(let reasons) = DeviceTakeRelease.check(deviceTake: deviceTake, driveTake: driveTake, shouldStop: { false }) else {
            Issue.record("not refused"); return
        }
        #expect(reasons.first?.contains("channel 1") == true)
    }

    @Test("A stand-in Stem holding more than its listed range, which the Drive never had, keeps the Take (#871)")
    func standInTailKept() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = try make(deviceFrames: [3_000], driveFrames: [5_000])
        metadata.standIns = [.init(start: 3_000, end: 5_000)]
        try metadata.write(to: deviceTake)
        // An abandoned standby's Stem: frames 3,000 to 5,500, past the end its Take.json lists.
        let standIn = deviceTake.appending(path: metadata.standIns![0].folderName).appending(path: Self.channel(1).stemFile)
        try FileManager.default.createDirectory(at: standIn.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "Test", timeReference: 3_000, originationDate: Self.startedAt)
        let stem = try StemWriter(url: standIn, info: info)
        try (3_000..<5_500).map { counting()($0, 0) }.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()

        guard case .kept = run() else { Issue.record("not kept"); return }
        #expect(FileManager.default.fileExists(atPath: standIn.path))
    }
}

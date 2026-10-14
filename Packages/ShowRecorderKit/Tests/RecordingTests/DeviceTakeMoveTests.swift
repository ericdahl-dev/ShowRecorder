import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#630): moving one Drive only Take the Device holds whole to the Drive, from Take folders made by hand.
@Suite("Moving a Take the Device holds whole")
struct DeviceTakeMoveTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "DeviceTakeMoveTests-\(UUID().uuidString)")
    var deviceShow: URL { root.appending(path: "Device/2026-10-06 Show") }
    var deviceTake: URL { deviceShow.appending(path: "Take 01") }
    var driveParent: URL { root.appending(path: "Drive") }
    var driveShow: URL { driveParent.appending(path: "2026-10-06 Show") }
    var driveTake: URL { driveShow.appending(path: "Take 01") }
    static let startedAt = Date(timeIntervalSince1970: 1_791_331_200)

    /// A Stem holding `frames` of channel `channel`'s counting samples, silent over `silent`.
    func writeStem(_ url: URL, frames: Int, channel: Int, silent: Range<Int>? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "Test", timeReference: 0, originationDate: Self.startedAt)
        let stem = try StemWriter(url: url, info: info)
        let samples = (0..<frames).map { silent?.contains($0) == true ? 0 : counting()($0, channel - 1) }
        try samples.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    /// A Drive only Take of `frames` the Device holds whole, and none on the Drive.
    @discardableResult
    func make(channels: Int = 1, frames: Int = 4_800) throws -> TakeMetadata {
        let list = (1...channels).map { StandInMoveTests.channel($0) }
        var metadata = TakeMetadata(show: "2026-10-06 Show", take: 1, startedAt: Self.startedAt, sampleRate: 48_000, timeReference: 0, usbChannels: list)
        metadata.driveOnly = true
        try FileManager.default.createDirectory(at: deviceTake, withIntermediateDirectories: true)
        try metadata.write(to: deviceTake)
        for channel in list { try writeStem(deviceTake.appending(path: channel.stemFile), frames: frames, channel: channel.usbChannel) }
        try FileManager.default.createDirectory(at: driveParent, withIntermediateDirectories: true)
        return metadata
    }

    /// A whole Drive Take of the same Take, as Repair leaves it after a Drive joined mid-Take.
    func makeDriveTake(_ metadata: TakeMetadata, frames: Int = 4_800, startedAt: Date = startedAt) throws {
        var onDrive = metadata
        onDrive.startedAt = startedAt
        try FileManager.default.createDirectory(at: driveTake, withIntermediateDirectories: true)
        try onDrive.write(to: driveTake)
        for channel in metadata.usbChannels { try writeStem(driveTake.appending(path: channel.stemFile), frames: frames, channel: channel.usbChannel) }
    }

    func driveStem(_ channel: Int = 1) -> URL { driveTake.appending(path: StandInMoveTests.channel(channel).stemFile) }

    func run(shouldStop: @escaping () -> Bool = { false }, at hook: @escaping (StandInMove.Step) -> Void = { _ in }) -> StandInMove.Outcome {
        DeviceTakeMove.run(deviceTake: deviceTake, driveTake: driveTake, shouldStop: shouldStop, at: hook)
    }

    func reasons(_ outcome: StandInMove.Outcome) -> [String] {
        if case .kept(let reasons) = outcome { return reasons }
        Issue.record("not kept: \(outcome)")
        return []
    }

    @Test("A Take with none on the Drive is copied there, Repaired, and leaves the Device")
    func copiesToTheDrive() throws {
        try make()

        #expect(run() == .moved)
        #expect(try StemWriter.readSamples(url: driveStem(), frames: 0..<4_800) == (0..<4_800).map { counting()($0, 0) })
        let onDrive = try TakeMetadata.read(fromTakeFolder: driveTake)
        #expect(onDrive.gaps == [.init(copy: .drive, start: 0, end: 4_800)])
        #expect(onDrive.repairs == [.init(copy: .drive, start: 0, end: 4_800, outcome: .repaired)])
        #expect(!FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A Device Take already gone is nothing to do")
    func goneFromTheDevice() throws {
        #expect(run() == .gone)
    }

    @Test("A Drive Show folder that is a link is never written through")
    func driveShowIsALink() throws {
        try make()
        let elsewhere = root.appending(path: "Elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: driveShow, withDestinationURL: elsewhere)

        #expect(!reasons(run()).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty, "nothing written through the link")
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path))
    }

    @Test("A Drive Take of another recording is kept, and the Drive left as it was")
    func anotherRecordingOnTheDrive() throws {
        let metadata = try make()
        try makeDriveTake(metadata, startedAt: Self.startedAt.addingTimeInterval(60))
        let before = try Data(contentsOf: driveStem())

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("another recording") }, "\(reasons)")
        #expect(try Data(contentsOf: driveStem()) == before)
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path))
    }

    @Test("A whole Drive Take of the same recording is checked and the Device's Take removed")
    func redundantOnTheDevice() throws {
        let metadata = try make()
        try makeDriveTake(metadata)

        #expect(run() == .moved)
        #expect(!FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A Device Take holding other files than its Take.json and Stems is kept, with why")
    func strayFileOnTheDevice() throws {
        try make()
        try Data("notes".utf8).write(to: deviceTake.appending(path: "notes.txt"))

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("notes.txt") }, "\(reasons)")
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "notes.txt").path))
    }

    @Test("A .DS_Store the Finder left in the Device's Take doesn't keep it")
    func finderFileDoesntKeepTheTake() throws {
        try make()
        try Data().write(to: deviceTake.appending(path: ".DS_Store"))

        #expect(run() == .moved)
    }

    @Test("A Drive that changes after it is filled is no false Repair: the Take is kept, the half-made Drive Take removed, and a later move succeeds")
    func noRepairRecordedBeforeTheCheck() throws {
        try make()

        let outcome = run(at: { step in
            if step == .filled { try? self.writeStem(self.driveStem(), frames: 4_800, channel: 1, silent: 0..<100) }
        })

        #expect(!reasons(outcome).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: driveTake.path), "the half-made Drive Take is removed")
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path))

        #expect(run() == .moved)
    }

    @Test("A set-aside folder left by an earlier move keeps the Take, and says so")
    func leftoverSetAside() throws {
        try make()
        try FileManager.default.createDirectory(at: deviceShow.appending(path: ".moved Take 01"), withIntermediateDirectories: true)

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains(".moved Take 01") }, "\(reasons)")
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path))
    }

    @Test("A second check that fails puts the Device's Take back")
    func secondCheckFails() throws {
        try make()

        let outcome = run(at: { step in
            if step == .setAside { try? self.writeStem(self.driveStem(), frames: 4_800, channel: 1, silent: 0..<100) }
        })

        #expect(!reasons(outcome).isEmpty)
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path))
        #expect(!FileManager.default.fileExists(atPath: deviceShow.appending(path: ".moved Take 01").path))
    }

    @Test("A set-aside folder that can't be removed is reported, not taken for a move")
    func setAsideNotRemoved() throws {
        try make()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deviceShow.path) }

        let outcome = run(at: { step in
            if step == .removing { try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: deviceShow.path) }
        })

        #expect(reasons(outcome).contains { $0.contains("couldn't be removed") }, "\(outcome)")
    }

    @Test("A Take started while the Drive's copy is made stops it, removes the half-made Drive Take, and a later move finishes")
    func stopRemovesTheHalfMadeDriveTake() throws {
        try make(channels: 2)
        var asked = 0

        #expect(run(shouldStop: { asked += 1; return asked > 1 }) == .stopped)
        #expect(!FileManager.default.fileExists(atPath: driveTake.path), "the half-made Drive Take is gone")
        #expect(!FileManager.default.fileExists(atPath: driveShow.path), "and the Show folder this move made for it")
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "02 USB 02.wav").path))

        #expect(run() == .moved)
        #expect(try StemWriter.readSamples(url: driveStem(2), frames: 0..<4_800) == (0..<4_800).map { counting()($0, 1) })
    }

    /// A Show.json for the Show in `folder`, started at `startedAt`.
    func writeShowFile(to folder: URL, startedAt: Date = startedAt) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ShowFile(name: "2026-10-06 Show", startedAt: startedAt).write(to: folder)
    }

    @Test("A cut-off Take whose Stems aren't all one length is kept, with why, and nothing is made on the Drive")
    func unequalStemsOnTheDevice() throws {
        try make(channels: 2)
        try writeStem(deviceTake.appending(path: "02 USB 02.wav"), frames: 4_000, channel: 2)

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("channel 2") }, "\(reasons)")
        #expect(!FileManager.default.fileExists(atPath: driveShow.path), "nothing on the Drive")
    }

    @Test("A Drive Show.json that can't be read is never written over: the Take is kept, with why")
    func unreadableShowFileOnTheDrive() throws {
        try make()
        try writeShowFile(to: deviceShow)
        try FileManager.default.createDirectory(at: driveShow, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: driveShow.appending(path: "Show.json"))

        #expect(!reasons(run()).isEmpty)
        #expect(try Data(contentsOf: driveShow.appending(path: "Show.json")) == Data("not JSON".utf8))
        #expect(!FileManager.default.fileExists(atPath: driveTake.path))
    }

    @Test("A Drive Show of the same name started at another time is another Show: the Take is kept, nothing written")
    func anotherShowOnTheDrive() throws {
        try make()
        try writeShowFile(to: deviceShow)
        try writeShowFile(to: driveShow, startedAt: Self.startedAt.addingTimeInterval(3_600))
        let before = try Data(contentsOf: driveShow.appending(path: "Show.json"))

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("another Show") }, "\(reasons)")
        #expect(try Data(contentsOf: driveShow.appending(path: "Show.json")) == before)
        #expect(!FileManager.default.fileExists(atPath: driveTake.path))
    }

    @Test("A Drive Take missing one of the Device's channels keeps the Device's Take untouched")
    func driveTakeMissingAChannel() throws {
        let metadata = try make(channels: 2)
        var onDrive = metadata
        onDrive.usbChannels = [metadata.usbChannels[0]]
        try FileManager.default.createDirectory(at: driveTake, withIntermediateDirectories: true)
        try onDrive.write(to: driveTake)
        try writeStem(driveStem(1), frames: 4_800, channel: 1)
        let before = try Data(contentsOf: deviceTake.appending(path: "02 USB 02.wav"))

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("channel 2") }, "\(reasons)")
        #expect(try Data(contentsOf: deviceTake.appending(path: "02 USB 02.wav")) == before)
    }
}

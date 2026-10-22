import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#630): a move cut off by a crash after the Device's Take was set aside (`.moved Take NN`) and before it
/// was deleted is finished when the Drive still holds the Take, and undone when it doesn't.
@Suite("A move cut off by a crash")
struct MoveRecoveryTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "MoveRecoveryTests-\(UUID().uuidString)")
    var deviceFolder: URL { root.appending(path: "Device") }
    var driveFolder: URL { root.appending(path: "Drive") }
    var deviceShow: URL { deviceFolder.appending(path: "2026-10-06 Show") }
    var setAside: URL { deviceShow.appending(path: ".moved Take 01") }
    var deviceTake: URL { deviceShow.appending(path: "Take 01") }
    var driveTake: URL { driveFolder.appending(path: "2026-10-06 Show/Take 01") }
    var driveStem: URL { driveTake.appending(path: "01 USB 01.wav") }

    func writeStem(_ url: URL, frames: Range<Int>, silent: Range<Int>? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "Test", timeReference: 0, originationDate: StandInMoveTests.startedAt)
        let stem = try StemWriter(url: url, info: info)
        let samples = frames.map { silent?.contains($0) == true ? 0 : counting()($0, 0) }
        try samples.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    /// A whole Drive only Take set aside on the Device after its first check, and its whole Drive Take.
    func setAsideWholeTake() throws {
        var metadata = TakeMetadata(
            show: "2026-10-06 Show", take: 1, startedAt: StandInMoveTests.startedAt, sampleRate: 48_000, timeReference: 0,
            usbChannels: [StandInMoveTests.channel(1)])
        metadata.driveOnly = true
        for folder in [setAside, driveTake] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try metadata.write(to: folder)
            try writeStem(folder.appending(path: "01 USB 01.wav"), frames: 0..<4_800)
        }
    }

    /// A kept stand-in set aside on the Device after its first check, and its Drive Take, whose Take.json lists the
    /// stand-in when `listed`.
    func setAsideStandIn(listed: Bool) throws {
        let metadata = StandInMoveTests.metadata([StandInMoveTests.channel(1)], standIn: .init(start: 0, end: 7_200), gaps: [])
        try FileManager.default.createDirectory(at: setAside, withIntermediateDirectories: true)
        try metadata.write(to: setAside)
        try writeStem(setAside.appending(path: "Stand-in 0/01 USB 01.wav"), frames: 0..<7_200)
        var onDrive = metadata
        if !listed { onDrive.standIns = nil }
        try FileManager.default.createDirectory(at: driveTake, withIntermediateDirectories: true)
        try onDrive.write(to: driveTake)
        try writeStem(driveStem, frames: 0..<7_200)
    }

    func recover() -> [StandInMove.Result] { MoveRecovery.run(deviceFolder: deviceFolder, driveFolder: driveFolder) }

    func kept(_ results: [StandInMove.Result]) -> [String] {
        guard results.count == 1, case .kept(let reasons) = results[0].outcome else {
            Issue.record("not kept once: \(results)")
            return []
        }
        return reasons
    }

    @Test("A set-aside Take whose Drive Take changed is put back as Take 01, and nothing is deleted")
    func driveChangedPutsItBack() throws {
        try setAsideWholeTake()
        try writeStem(driveStem, frames: 0..<4_800, silent: 0..<100)

        #expect(!kept(recover()).isEmpty)
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "01 USB 01.wav").path), "Take 01 is back")
        #expect(!FileManager.default.fileExists(atPath: setAside.path))
        #expect(FileManager.default.fileExists(atPath: driveStem.path))
    }

    @Test("A set-aside Take whose Drive Take is gone is put back as Take 01")
    func driveTakeGonePutsItBack() throws {
        try setAsideWholeTake()
        try FileManager.default.removeItem(at: driveTake)

        #expect(!kept(recover()).isEmpty)
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path))
    }

    @Test("A set-aside stand-in whose Drive changed is put back, and the Drive's Take.json lists the stand-in again")
    func standInPutBackRestoresTheList() throws {
        try setAsideStandIn(listed: false)
        try writeStem(driveStem, frames: 0..<7_200, silent: 0..<100)

        #expect(!kept(recover()).isEmpty)
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Stand-in 0/01 USB 01.wav").path))
        #expect(try TakeMetadata.read(fromTakeFolder: driveTake).standIns == [.init(start: 0, end: 7_200)])
    }

    @Test("A set-aside Take the Drive still holds whole is deleted: the move is finished")
    func driveWholeFinishesTheMove() throws {
        try setAsideWholeTake()

        #expect(recover() == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(!FileManager.default.fileExists(atPath: setAside.path))
        #expect(!FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A set-aside Take with a staged Take.json a crash left in it is still deleted: the move is finished (#914)")
    func stagedTakeJsonDoesntStopRecovery() throws {
        try setAsideWholeTake()
        try Data().write(to: setAside.appending(path: ".Take.json.\(UUID().uuidString)"))

        #expect(recover() == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(!FileManager.default.fileExists(atPath: setAside.path))
    }

    @Test("A set-aside Take with a hidden file that only looks like a staged Take.json is put back, not deleted (#914)")
    func lookAlikeIsPutBack() throws {
        try setAsideWholeTake()
        try Data().write(to: setAside.appending(path: ".Take.json.tmp"))

        let reasons = kept(recover())

        #expect(reasons.contains { $0.contains(".Take.json.tmp") }, "\(reasons)")
    }

    @Test("A set-aside stand-in the Drive holds is deleted, and the stand-in still listed on the Drive is cleared")
    func standInFinishedClearsTheList() throws {
        try setAsideStandIn(listed: true)

        #expect(recover() == [.init(show: "2026-10-06 Show", take: 1, outcome: .moved)])
        #expect(!FileManager.default.fileExists(atPath: setAside.path))
        #expect(try TakeMetadata.read(fromTakeFolder: driveTake).standIns == nil)
    }

    @Test("With Take 01 on the Device too, neither it nor the set-aside folder is touched, and that is reported")
    func bothOnTheDevice() throws {
        try setAsideWholeTake()
        try FileManager.default.copyItem(at: setAside, to: deviceTake)

        let reasons = kept(recover())

        #expect(reasons.contains { $0.contains(".moved Take 01") }, "\(reasons)")
        #expect(FileManager.default.fileExists(atPath: setAside.appending(path: "01 USB 01.wav").path))
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "01 USB 01.wav").path))
    }

    @Test("Only folders named exactly .moved Take NN are looked at")
    func otherHiddenFilesAreLeftAlone() throws {
        try setAsideWholeTake()
        try FileManager.default.moveItem(at: setAside, to: deviceShow.appending(path: ".moved Take 1"))
        for name in [".DS_Store", ".moved Take 01.txt", ".movedTake 01"] {
            try Data().write(to: deviceShow.appending(path: name))
        }

        #expect(recover().isEmpty)
        #expect(FileManager.default.fileExists(atPath: deviceShow.appending(path: ".moved Take 1/Take.json").path))
    }

    @Test("A set-aside Take holding other files than its own is put back, not deleted, though the Drive holds it")
    func strayFileIsPutBack() throws {
        try setAsideWholeTake()
        try Data("notes".utf8).write(to: setAside.appending(path: "notes.txt"))

        let reasons = kept(recover())

        #expect(reasons.contains { $0.contains("notes.txt") }, "\(reasons)")
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "notes.txt").path))
    }

    @Test("A set-aside Take whose folder can't be listed is put back, not deleted")
    func unlistableIsPutBack() throws {
        try setAsideWholeTake()
        try FileManager.default.setAttributes([.posixPermissions: 0o311], ofItemAtPath: setAside.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setAside.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deviceTake.path)
        }

        let reasons = kept(recover())

        #expect(reasons.contains { $0.contains("can't be listed") }, "\(reasons)")
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A stand-in that can't be put back isn't listed on the Drive again")
    func noReListingWithoutPuttingBack() throws {
        try setAsideStandIn(listed: false)
        try writeStem(driveStem, frames: 0..<7_200, silent: 0..<100)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: deviceShow.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deviceShow.path) }

        let reasons = kept(recover())

        #expect(reasons.contains { $0.contains("couldn't be put back") }, "\(reasons)")
        #expect(try TakeMetadata.read(fromTakeFolder: driveTake).standIns == nil)
    }

    @Test("A Take started during recovery stops it before the next set-aside Take")
    func stopsBetweenTakes() throws {
        try setAsideWholeTake()
        let second = deviceShow.appending(path: ".moved Take 02")
        try FileManager.default.copyItem(at: setAside, to: second)
        var asked = 0

        let results = MoveRecovery.run(deviceFolder: deviceFolder, driveFolder: driveFolder, shouldStop: { asked += 1; return asked > 1 })

        #expect(results.map(\.take) == [1])
        #expect(FileManager.default.fileExists(atPath: second.path), "the second is left for later")
    }
}

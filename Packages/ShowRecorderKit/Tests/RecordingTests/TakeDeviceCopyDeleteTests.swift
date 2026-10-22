import Foundation
import ShowReport
@testable import Recording
import TakeFile
import Testing

/// Deleting one Take's Device copy checks the Drive first, as deleting a whole Show's does (#925).
extension RecorderReleaseTests {
    @Test("A Take's Device copy is deleted once the Drive holds everything it holds, and the Drive copy stays (#925)")
    func takeDeviceCopyDeletedWhenTheDriveHoldsIt() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()

        let outcome = await recorder().deleteDeviceCopy(of: "2026-10-06 Show", take: 1)

        #expect(outcome.deleted == [.device] && outcome.failed.isEmpty, "\(outcome.failed)")
        #expect(!FileManager.default.fileExists(atPath: deviceTake.path))
        #expect(FileManager.default.fileExists(atPath: driveTake.appending(path: "Take.json").path))
    }

    @Test("A Take's Device copy holding audio the Drive lacks is kept, with why, and nothing is deleted (#925)")
    func takeDeviceCopyKeptWhenTheDriveLacksAudio() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        try writeStem(driveTake.appending(path: DeviceTakeReleaseTests.channel(1).stemFile), frames: 2_000, channel: 1)

        let outcome = await recorder().deleteDeviceCopy(of: "2026-10-06 Show", take: 1)

        #expect(outcome.deleted.isEmpty)
        #expect(!outcome.failed.isEmpty && outcome.failed.allSatisfy { $0.copy == .device && !$0.reason.isEmpty })
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    /// Makes the kept Take an ordinary one, recorded to the Device: not Drive only.
    func makeOrdinary() throws {
        var metadata = try TakeMetadata.read(fromTakeFolder: deviceTake)
        metadata.driveOnly = nil
        try metadata.write(to: deviceTake)
    }

    @Test("An ordinary Take with no Drive is the only copy: its Device copy is deleted as before (#925)")
    func ordinaryTakeWithNoDrive() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        try makeOrdinary()

        let outcome = await recorder(withDrive: false).deleteDeviceCopy(of: "2026-10-06 Show", take: 1)

        #expect(outcome.deleted == [.device] && outcome.failed.isEmpty, "\(outcome.failed)")
        #expect(!FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("An ordinary Take the connected Drive doesn't have is the only copy: its Device copy is deleted (#925)")
    func ordinaryTakeNotOnTheDrive() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        try makeOrdinary()
        try FileManager.default.removeItem(at: driveTake)

        let outcome = await recorder().deleteDeviceCopy(of: "2026-10-06 Show", take: 1)

        #expect(outcome.deleted == [.device] && outcome.failed.isEmpty, "\(outcome.failed)")
    }

    @Test("A Take recorded for the Drive isn't deleted from the Device while its Drive isn't there, with why (#925)")
    func driveOnlyTakeWithNoDrive() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()

        let outcome = await recorder(withDrive: false).deleteDeviceCopy(of: "2026-10-06 Show", take: 1)

        #expect(outcome.deleted.isEmpty)
        #expect(outcome.failed.map(\.reason) == ["This Take was recorded for the Drive. Connect that Drive, so it can be checked first."])
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("After a Take's Device copy is deleted, the Device's Show report and Reaper project no longer list it (#925)")
    func reportRewrittenAfterTheDelete() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        try makeOrdinary()
        let showFolder = device.appending(path: "2026-10-06 Show")
        try ShowReport.write(showFolder: showFolder)
        #expect(try String(contentsOf: showFolder.appending(path: "Report.html"), encoding: .utf8).contains("Take 01"))

        let outcome = await recorder().deleteDeviceCopy(of: "2026-10-06 Show", take: 1)

        #expect(outcome.deleted == [.device], "\(outcome.failed)")
        #expect(!(try String(contentsOf: showFolder.appending(path: "Report.html"), encoding: .utf8)).contains("Take 01"))
        #expect(!(try String(contentsOf: showFolder.appending(path: "2026-10-06 Show.rpp"), encoding: .utf8)).contains("Take 01/"))
    }

    @Test("A Take with stand-ins isn't deleted from the Device while no Drive is there, even without the Drive only mark (#925)")
    func standInsWithNoDrive() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        var metadata = try TakeMetadata.read(fromTakeFolder: deviceTake)
        metadata.driveOnly = nil
        metadata.standIns = [.init(start: 0, end: 0)]
        try metadata.write(to: deviceTake)

        let outcome = await recorder(withDrive: false).deleteDeviceCopy(of: "2026-10-06 Show", take: 1)

        #expect(outcome.deleted.isEmpty)
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A Take whose details can't be read isn't deleted from the Device unchecked, with why (#925)")
    func unreadableTakeKept() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        try Data("not a Take".utf8).write(to: deviceTake.appending(path: "Take.json"))

        let outcome = await recorder(withDrive: false).deleteDeviceCopy(of: "2026-10-06 Show", take: 1)

        #expect(outcome.deleted.isEmpty)
        #expect(outcome.failed.map(\.reason) == ["This Take's details can't be read on the Device, so it can't be checked against the Drive."])
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("Sheet and delete agree: the check passes for a Take that is the Device's only copy, and fails where the delete refuses (#925)")
    func checkMatchesTheDelete() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        try makeOrdinary()
        try FileManager.default.removeItem(at: driveTake)
        #expect(await recorder().checkDeviceCopyDelete(of: "2026-10-06 Show", take: 1) == .passed)

        var metadata = try TakeMetadata.read(fromTakeFolder: deviceTake)
        metadata.driveOnly = true
        try metadata.write(to: deviceTake)
        guard case .failed = await recorder().checkDeviceCopyDelete(of: "2026-10-06 Show", take: 1) else { Issue.record("passed"); return }
    }

    @Test("A Take recorded to both Copies whose Drive copy lacks audio the Device holds is kept on the Device (#925)")
    func bothCopiesDriveShortKept() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeKeptTake()
        try makeOrdinary()
        try writeStem(driveTake.appending(path: DeviceTakeReleaseTests.channel(2).stemFile), frames: 1_000, channel: 2)

        let outcome = await recorder().deleteDeviceCopy(of: "2026-10-06 Show", take: 1)

        #expect(outcome.deleted.isEmpty && !outcome.failed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
        guard case .failed = await recorder().checkDeviceCopyDelete(of: "2026-10-06 Show", take: 1) else { Issue.record("passed"); return }
    }
}

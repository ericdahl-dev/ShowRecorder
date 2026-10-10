import AudioIO
import Destinations
import Foundation
import Testing

@testable import Recording

/// The Show list: past Shows read from the files, newest first.
@MainActor
@Suite("Show list")
struct ShowListTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    @MainActor final class Clock { var now = RecordingTakeTests.showDay }
    let clock = Clock()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShowListTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorder(withDrive: Bool = false) -> Recorder {
        let clock = clock, drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { withDrive ? DestinationAccess(folder: drive) : nil },
            now: { MainActor.assumeIsolated { clock.now } })
    }

    func record(_ recorder: Recorder) throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.1, count: 480)])
        try recorder.stopTake()
        recorder.disarm()
    }

    @Test("A Shows folder that can't be read is a failure, not an empty list")
    func unreadableFolder() throws {
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: device.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: device.path) }

        #expect(ShowList.load(device: device, drive: nil) == .unreadable)
    }

    @Test("A Shows folder that is empty or not made yet is no Shows, and Shows come back as Shows")
    func emptyIsNotFailure() throws {
        #expect(ShowList.load(device: device, drive: nil) == .shows([]))
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        #expect(ShowList.load(device: device, drive: drive) == .shows([]))
        try record(recorder())
        guard case .shows(let shows) = ShowList.load(device: device, drive: nil) else { Issue.record("expected Shows"); return }
        #expect(shows.count == 1)
    }

    @Test("Shows are listed newest first with their start, Take count and duration from first Take start to last Take end")
    func newestFirst() throws {
        let recorder = recorder()
        try record(recorder)
        clock.now = clock.now.addingTimeInterval(3600)
        try record(recorder)
        try recorder.endShow()
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(recorder)

        let shows = ShowList.read(device: device, drive: nil)
        #expect(shows.map(\.name) == ["2026-10-07 Show", "2026-10-06 Show"])
        #expect(shows.map(\.takeCount) == [1, 2])
        #expect(shows[1].startedAt == RecordingTakeTests.showDay)
        // Second Take starts 3600 s in and lasts 480 frames at 48 kHz (0.01 s).
        #expect(abs(shows[1].duration - 3600.01) < 0.001)
    }

    @Test("A Show on both Copies says complete for each; a Show on the Device only has no Drive Copy")
    func copyStates() throws {
        let both = recorder(withDrive: true)
        try record(both)
        try both.endShow()
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(recorder())

        let shows = ShowList.read(device: device, drive: drive)
        #expect(shows[1].deviceCopy == .complete)
        #expect(shows[1].driveCopy == .complete)
        #expect(shows[0].deviceCopy == .complete)
        #expect(shows[0].driveCopy == nil, "not there")
    }

    /// Rewrites a Take's Take.json in both Copies, as Repair leaves it.
    func edit(_ takeFolder: URL, _ change: (inout TakeMetadata) -> Void) throws {
        for folder in [takeFolder, drive.appending(path: takeFolder.deletingLastPathComponent().lastPathComponent).appending(path: takeFolder.lastPathComponent)] {
            try editOne(folder, change)
        }
    }

    func editOne(_ takeFolder: URL, _ change: (inout TakeMetadata) -> Void) throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        let url = takeFolder.appending(path: TakeMetadata.fileName)
        var take = try decoder.decode(TakeMetadata.self, from: Data(contentsOf: url))
        change(&take)
        try encoder.encode(take).write(to: url)
    }

    @Test("A Copy's state is the worst of its Takes: has Gaps, Repaired or Repair failed")
    func gapsAndRepairs() throws {
        let both = recorder(withDrive: true)
        try record(both)
        clock.now = clock.now.addingTimeInterval(60)
        try record(both)
        let take1 = device.appending(path: "2026-10-06 Show/Take 01")
        let take2 = device.appending(path: "2026-10-06 Show/Take 02")
        try edit(take1) { $0.gaps = [.init(copy: .drive, start: 0, end: 10)] }
        #expect(ShowList.read(device: device, drive: drive)[0].driveCopy == .hasGaps)
        #expect(ShowList.read(device: device, drive: drive)[0].deviceCopy == .complete)

        try edit(take1) { $0.repairs = [.init(copy: .drive, start: 0, end: 10, outcome: .repaired)] }
        #expect(ShowList.read(device: device, drive: drive)[0].driveCopy == .repaired)

        try edit(take2) {
            $0.gaps = [.init(copy: .drive, start: 0, end: 5)]
            $0.repairs = [.init(copy: .drive, start: 0, end: 5, outcome: .failed)]
        }
        #expect(ShowList.read(device: device, drive: drive)[0].driveCopy == .repairFailed)
    }

    @Test("An empty Show, a Show on the Drive only and an old Show with no Show.json all list without error")
    func oddShows() throws {
        let both = recorder(withDrive: true)
        try both.startNewShow(name: "Empty", venue: "")
        try both.endShow()

        // An old Show: Takes, but no Show.json on either Copy.
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(both)
        try both.endShow()
        for parent in [device, drive] {
            try FileManager.default.removeItem(at: parent.appending(path: "2026-10-07 Show/Show.json"))
        }

        // A Show only on the Drive: the Device Copy was lost.
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(48 * 3600)
        try record(both)
        try FileManager.default.removeItem(at: device.appending(path: "2026-10-08 Show"))

        let shows = ShowList.read(device: device, drive: drive)
        #expect(shows.map(\.name) == ["2026-10-08 Show", "2026-10-07 Show", "2026-10-06 Empty"])
        #expect(shows[0].deviceCopy == nil)
        #expect(shows[0].driveCopy == .complete)
        #expect(shows[1].takeCount == 1)
        #expect(shows[1].startedAt == RecordingTakeTests.showDay.addingTimeInterval(24 * 3600), "from its first Take")
        #expect(shows[2].takeCount == 0)
        #expect(shows[2].duration == 0)
    }

    @Test("A Show can be shared from the Device Copy when it has one, and not when only the Drive does")
    func shareFolder() throws {
        let both = recorder(withDrive: true)
        try record(both)
        try both.endShow()
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(both)
        try FileManager.default.removeItem(at: device.appending(path: "2026-10-07 Show"))

        let shows = ShowList.read(device: device, drive: drive)
        #expect(shows[1].shareFolder == device.appending(path: "2026-10-06 Show", directoryHint: .isDirectory))
        #expect(shows[0].shareFolder == nil, "only on the Drive")
        // What is shared is the whole Show folder: Stems, report and Reaper project.
        let contents = try FileManager.default.contentsOfDirectory(atPath: try #require(shows[1].shareFolder).path)
        #expect(contents.contains("Report.html") && contents.contains("2026-10-06 Show.RPP") && contents.contains("Take 01"))
    }

    @Test("Show.json says a Drive Copy was written once one was, in both Copies; a Device-only Show says not")
    func showFileRemembersDrive() throws {
        let both = recorder(withDrive: true)
        try record(both)
        try both.endShow()
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(recorder())

        #expect(ShowFile.read(from: device.appending(path: "2026-10-06 Show"))?.driveCopyWritten == true)
        #expect(ShowFile.read(from: drive.appending(path: "2026-10-06 Show"))?.driveCopyWritten == true)
        #expect(ShowFile.read(from: device.appending(path: "2026-10-07 Show"))?.driveCopyWritten != true)
    }

    @Test("The Copy note: nothing when both Copies are complete, 'No Drive copy' when a Drive Copy never existed, 'Drive not connected now' when one was written but the Drive is away")
    func copyNote() throws {
        let both = recorder(withDrive: true)
        try record(both)
        try both.endShow()
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(recorder())

        let connected = ShowList.read(device: device, drive: drive)
        #expect(connected[1].copyNote == nil, "both complete")
        #expect(connected[0].copyNote == CopyNote(text: "No Drive copy", severity: .warning), "never written")

        let away = ShowList.read(device: device, drive: nil)
        #expect(away[1].copyNote == CopyNote(text: "Drive not connected now", severity: .warning), "written, Drive away")
        #expect(away[0].copyNote == CopyNote(text: "No Drive copy", severity: .warning))
    }

    @Test("Gaps and a failed Repair are a problem; Repaired is fine; an old Show.json without the field still lists")
    func copyNoteProblemsAndOldShows() throws {
        func summary(_ device: CopyOutcome?, _ drive: CopyOutcome?, written: Bool? = true, connected: Bool = true) -> ShowSummary {
            ShowSummary(name: "S", folder: root, startedAt: .distantPast, takeCount: 1, duration: 0, deviceCopy: device, driveCopy: drive,
                        driveCopyWritten: written, driveConnected: connected)
        }
        #expect(summary(.complete, .repaired).copyNote == nil)
        #expect(summary(.complete, .hasGaps).copyNote == CopyNote(text: "Drive copy has Gaps", severity: .problem))
        #expect(summary(.repairFailed, .complete).copyNote == CopyNote(text: "Device Repair failed", severity: .problem))
        #expect(summary(.complete, nil, connected: true).copyNote?.text == "Drive copy missing")
        #expect(summary(.complete, nil, written: nil, connected: false).copyNote?.text == "No Drive copy")

        let old = device.appending(path: "2026-10-01 Old")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data(#"{"name":"2026-10-01 Old","startedAt":"2026-10-01T20:00:00Z"}"#.utf8).write(to: old.appending(path: "Show.json"))
        let listed = ShowList.read(device: device, drive: drive).first { $0.name == "2026-10-01 Old" }
        #expect(listed?.driveCopyWritten == nil)
        #expect(listed?.copyNote?.text == "No Drive copy")
    }
}

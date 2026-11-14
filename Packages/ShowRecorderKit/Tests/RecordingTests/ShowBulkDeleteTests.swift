import AudioIO
import Destinations
import Foundation
import Testing

@testable import Recording

/// Deleting several Shows at once from the Shows list's Select mode (#1217): every Copy each Show has goes, the open
/// Show never does, and nothing goes during a Take.
@MainActor
@Suite("Delete several Shows")
struct ShowBulkDeleteTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ShowBulkDeleteTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    func makeShow(_ name: String, in parents: [URL]) throws {
        for parent in parents {
            try FileManager.default.createDirectory(at: parent.appending(path: name).appending(path: "Take 01"), withIntermediateDirectories: true)
        }
    }

    func exists(_ parent: URL, _ name: String) -> Bool { FileManager.default.fileExists(atPath: parent.appending(path: name).path) }

    func recorder() -> Recorder {
        let drive = drive
        return Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
    }

    @Test("Each Show goes from every Copy it has: Device and Drive, or the Device alone")
    func everyCopy() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeShow("2026-11-09 Show", in: [device, drive])
        try makeShow("2026-11-12 Show", in: [device])
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let shows = ShowList.read(device: device, drive: drive)

        let outcomes = await recorder().deleteShowsOffMain(shows)

        #expect(outcomes.map(\.name) == shows.map(\.name))
        #expect(outcomes.first { $0.name == "2026-11-09 Show" }?.outcome.deleted == [.device, .drive])
        #expect(outcomes.first { $0.name == "2026-11-12 Show" }?.outcome.deleted == [.device])
        #expect(outcomes.allSatisfy { $0.outcome.failed.isEmpty })
        #expect(!exists(device, "2026-11-09 Show") && !exists(drive, "2026-11-09 Show") && !exists(device, "2026-11-12 Show"))
    }

    @Test("Nothing is deleted during a Take")
    func duringTake() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeShow("2026-11-09 Show", in: [device])
        let shows = ShowList.read(device: device, drive: nil)
        let recorder = recorder()
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))
        try recorder.startTake()

        let outcomes = await recorder.deleteShowsOffMain(shows)

        #expect(outcomes.allSatisfy { $0.outcome.deleted.isEmpty && !$0.outcome.failed.isEmpty })
        #expect(exists(device, "2026-11-09 Show"))
        try await recorder.stopTake()
    }
}

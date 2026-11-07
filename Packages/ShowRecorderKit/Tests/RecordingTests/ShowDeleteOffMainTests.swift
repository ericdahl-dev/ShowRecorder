import AudioIO
import Destinations
import Foundation
@testable import Recording
import Synchronization
import Testing

/// Deleting a Show from the Show list reaches the Drive off the main thread (#1021). Resolving the Drive's bookmark,
/// reading its free space and removing its folder can block on a Drive that answers slowly, and a main thread blocked
/// long enough is ended by iOS, which looks like a crash.
@MainActor
@Suite("Delete a Show off the main thread")
struct ShowDeleteOffMainTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ShowDeleteOffMainTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let show = "2026-09-01 Old Show"

    /// One Show with one Take folder in each Copy.
    func makeShow() throws {
        for parent in [device, drive] {
            try FileManager.default.createDirectory(at: parent.appending(path: show).appending(path: "Take 01"), withIntermediateDirectories: true)
        }
    }

    func exists(_ parent: URL) -> Bool {
        FileManager.default.fileExists(atPath: parent.appending(path: show).path)
    }

    @Test("A Show delete asks for the Drive folder on its own thread, not the main thread")
    func driveResolvedOffMain() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeShow()
        let drive = drive
        let askedOnMain = Mutex<[Bool]>([])
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { askedOnMain.withLock { $0.append(Thread.isMainThread) }; return DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay })

        let outcome = await recorder.deleteShowOffMain(named: show, from: [.device, .drive])

        #expect(outcome.deleted == [.device, .drive])
        #expect(!exists(device) && !exists(drive))
        let asked = askedOnMain.withLock { $0 }
        #expect(!asked.isEmpty)
        #expect(!asked.contains(true), "the Drive folder was resolved on the main thread")
    }

    @Test("The Drive access taken for a Show delete is ended once the delete is done")
    func accessIsEnded() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeShow()
        let drive = drive
        let started = Mutex(0), ended = Mutex(0)
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { started.withLock { $0 += 1 }; return DriveAccess(folder: drive, stop: { ended.withLock { $0 += 1 } }) },
            now: { RecordingTakeTests.showDay })

        _ = await recorder.deleteShowOffMain(named: show, from: [.device, .drive])

        #expect(started.withLock { $0 } == 1)
        #expect(ended.withLock { $0 } == 1)
    }

    @Test("A Device only delete never asks for the Drive")
    func deviceOnlyLeavesDriveAlone() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeShow()
        let asked = Mutex(0)
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { asked.withLock { $0 += 1 }; return nil },
            now: { RecordingTakeTests.showDay })

        let outcome = await recorder.deleteShowOffMain(named: show, from: [.device])

        #expect(outcome.deleted == [.device])
        #expect(asked.withLock { $0 } == 0)
        #expect(!exists(device) && exists(drive))
    }

    @Test("With the Drive gone, the Device copy is still deleted and the outcome says the Drive copy can't be reached")
    func driveGone() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeShow()
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay })

        let outcome = await recorder.deleteShowOffMain(named: show, from: [.device, .drive])

        #expect(outcome.deleted == [.device])
        #expect(outcome.failed == [ShowDeleter.Failure(copy: .drive, reason: "The Drive isn't available.")])
        #expect(!exists(device) && exists(drive))
    }

    @Test("A Show delete still refuses while a Take is running")
    func refusedDuringTake() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeShow()
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()

        let outcome = await recorder.deleteShowOffMain(named: show, from: [.device, .drive])

        #expect(outcome.deleted.isEmpty)
        #expect(exists(device) && exists(drive))
        try await recorder.stopTake()
        await recorder.waitForRepair()
    }
}

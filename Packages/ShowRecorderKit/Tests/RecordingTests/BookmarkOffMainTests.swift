import AudioIO
import Destinations
import Foundation
@testable import Recording
import Synchronization
import Testing

/// The Drive's bookmark is resolved off the main thread when the Show total is read (#673): resolving it can block on a
/// Drive that is wedged.
@MainActor
@Suite("Drive bookmark off the main thread")
struct BookmarkOffMainTests {
    @Test("The Show total asks for the Drive folder on its own thread, not the main thread")
    func resolvedOffMain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookmarkOffMainTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let askedOnMain = Mutex<[Bool]>([])
        let recorder = Recorder(
            deviceFolder: root.appending(path: "Device"),
            driveFolder: { askedOnMain.withLock { $0.append(Thread.isMainThread) }; return DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        try await recorder.stopTake()
        await recorder.waitForRepair()
        askedOnMain.withLock { $0 = [] }

        _ = await recorder.showRecordedSecondsOffMain(leavingOut: nil)
        let asked = askedOnMain.withLock { $0 }
        #expect(!asked.isEmpty)
        #expect(!asked.contains(true), "the Drive folder was resolved on the main thread")
    }

    @Test("The access taken for the Show total is ended once the read is done")
    func accessIsEnded() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BookmarkOffMainTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let started = Mutex(0), ended = Mutex(0)
        let recorder = Recorder(
            deviceFolder: root.appending(path: "Device"),
            driveFolder: { started.withLock { $0 += 1 }; return DriveAccess(folder: drive, stop: { ended.withLock { $0 += 1 } }) },
            now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        try await recorder.stopTake()
        await recorder.waitForRepair()
        let before = (started.withLock { $0 }, ended.withLock { $0 })
        _ = await recorder.showRecordedSecondsOffMain(leavingOut: nil)
        #expect(started.withLock { $0 } - before.0 == 1)
        #expect(ended.withLock { $0 } - before.1 == 1)
    }
}

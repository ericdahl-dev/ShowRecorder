import AudioIO
import Destinations
import Foundation
@testable import Recording
import Synchronization
import Testing

/// Deleting a Take or a channel's file, and the Drive checks before a Device only delete, reach the Drive off the main
/// thread (#1021), as a Show delete does. Resolving the Drive's bookmark and reading its folders can block on a Drive
/// that answers slowly, and iOS ends an app whose main thread is blocked long enough.
@MainActor
@Suite("Delete a Take off the main thread")
struct TakeDeleteOffMainTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "TakeDeleteOffMainTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    /// What the Drive folder closure saw, shared with it.
    final class Asks: Sendable {
        /// Whether each ask for the Drive folder came on the main thread.
        let onMain = Mutex<[Bool]>([])
        /// Whether the Drive is there when asked.
        let driveThere = Mutex(true)
    }
    let asks = Asks()

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorder() -> Recorder {
        let drive = drive, asks = asks
        return Recorder(
            deviceFolder: device,
            driveFolder: {
                asks.onMain.withLock { $0.append(Thread.isMainThread) }
                return asks.driveThere.withLock { $0 } ? DriveAccess(folder: drive) : nil
            },
            now: { RecordingTakeTests.showDay })
    }

    /// Records one Take to both Copies and ends its Show, then forgets the asks so far. Returns the Show's name.
    func recordShow(_ recorder: Recorder) async throws -> String {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        try await recorder.stopTake()
        await recorder.waitForRepair()
        let name = try #require(recorder.currentShow?.name)
        recorder.standDown()
        try recorder.endShow()
        asks.onMain.withLock { $0 = [] }
        return name
    }

    func takeExists(_ parent: URL, _ show: String) -> Bool {
        FileManager.default.fileExists(atPath: parent.appending(path: show).appending(path: TakeMetadata.name(take: 1)).path)
    }

    /// The Drive was asked for, and never on the main thread.
    func expectAskedOffMain(sourceLocation: SourceLocation = #_sourceLocation) {
        let asked = asks.onMain.withLock { $0 }
        #expect(!asked.isEmpty, "the Drive was never asked for", sourceLocation: sourceLocation)
        #expect(!asked.contains(true), "the Drive folder was resolved on the main thread", sourceLocation: sourceLocation)
    }

    @Test("A Take delete asks for the Drive folder on its own thread, not the main thread")
    func takeDeleteOffMain() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = recorder()
        let show = try await recordShow(recorder)

        let outcome = await recorder.deleteTakeOffMain(1, ofShow: show, from: [.device, .drive])

        #expect(outcome.deleted == [.device, .drive])
        #expect(!takeExists(device, show) && !takeExists(drive, show))
        expectAskedOffMain()
    }

    @Test("A channel file delete asks for the Drive folder on its own thread, not the main thread")
    func channelDeleteOffMain() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = recorder()
        let show = try await recordShow(recorder)

        let outcome = await recorder.deleteChannelOffMain(1, inTake: 1, ofShow: show, from: [.device, .drive])

        #expect(outcome.deleted == [.device, .drive])
        expectAskedOffMain()
    }

    @Test("Checking a Show's Drive copy asks for the Drive folder on its own thread, not the main thread")
    func driveCopyCheckOffMain() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = recorder()
        let show = try await recordShow(recorder)

        let result = await recorder.checkDriveCopy(of: show)

        #expect(result == .passed)
        expectAskedOffMain()
    }

    @Test("Checking a Take's Device copy delete asks for the Drive folder on its own thread, not the main thread")
    func deviceCopyCheckOffMain() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = recorder()
        let show = try await recordShow(recorder)

        _ = await recorder.checkDeviceCopyDelete(of: show, take: 1)

        expectAskedOffMain()
    }

    @Test("Deleting a Take's Device copy asks for the Drive folder on its own thread, not the main thread")
    func deviceCopyDeleteOffMain() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = recorder()
        let show = try await recordShow(recorder)

        _ = await recorder.deleteDeviceCopy(of: show, take: 1)

        expectAskedOffMain()
        #expect(takeExists(drive, show), "the Drive copy is kept")
    }

    @Test("With the Drive gone, a Take's Device copy is still deleted and the outcome says the Drive copy can't be reached")
    func driveGone() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = recorder()
        let show = try await recordShow(recorder)
        asks.driveThere.withLock { $0 = false }

        let outcome = await recorder.deleteTakeOffMain(1, ofShow: show, from: [.device, .drive])

        #expect(outcome.deleted == [.device])
        #expect(outcome.failed.map(\.copy) == [.drive])
        #expect(outcome.failed.first?.reason == "The Drive isn't available.")
        #expect(!takeExists(device, show) && takeExists(drive, show))
    }

    @Test("A Take or channel delete still refuses while a Take is running")
    func refusedDuringTake() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = recorder()
        let show = try await recordShow(recorder)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()

        #expect(await recorder.deleteTakeOffMain(1, ofShow: show, from: [.device, .drive]).deleted.isEmpty)
        #expect(await recorder.deleteChannelOffMain(1, inTake: 1, ofShow: show, from: [.device, .drive]).deleted.isEmpty)
        #expect(takeExists(device, show) && takeExists(drive, show))
        try await recorder.stopTake()
        await recorder.waitForRepair()
    }
}

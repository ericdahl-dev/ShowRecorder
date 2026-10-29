import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

/// The Show's recorded total is read off the main thread (#673): a Drive that hangs after Stop can't block the screen.
@MainActor
@Suite("Show total off the main thread")
struct ShowTotalOffMainTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ShowTotalOffMainTests-\(UUID().uuidString)")

    @Test("The off-main read gives the same total as the direct one, with and without the running Take left out")
    func sameTotal() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let recorder = Recorder(deviceFolder: root.appending(path: "Device"), driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        try await recorder.stopTake()
        await recorder.waitForRepair()

        let direct = try #require(recorder.showRecordedSeconds(leavingOut: nil))
        let offMain = await recorder.showRecordedSecondsOffMain(leavingOut: nil)
        #expect(abs(direct - 0.1) < 0.000_1)
        #expect(offMain == direct)
        let leftOut = await recorder.showRecordedSecondsOffMain(leavingOut: 1)
        #expect(leftOut == recorder.showRecordedSeconds(leavingOut: 1))
    }

    @Test("With no Show there is no total")
    func noShow() async {
        let recorder = Recorder(deviceFolder: root.appending(path: "Empty"), driveFolder: { nil }, now: { RecordingTakeTests.showDay })
        let total = await recorder.showRecordedSecondsOffMain(leavingOut: nil)
        #expect(total == nil)
    }
}

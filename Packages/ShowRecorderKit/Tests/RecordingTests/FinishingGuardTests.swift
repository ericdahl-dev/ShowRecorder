import AudioIO
import Foundation
@testable import Recording
import Testing

/// Stop is still synchronous, but it already says it is finishing (#652, part A): the guard the async Stop will need, so
/// no Take starts while the last one's Copies are being written. Today the answer never differs; it is the seam.
@MainActor
@Suite("Finishing guard")
struct FinishingGuardTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "FinishingGuardTests-\(UUID().uuidString)")

    @Test("While a Take finishes, a new Take is refused; once Stop returns, it starts")
    func refusedWhileFinishing() throws {
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        var finishingWhenTold: [Bool] = []
        var refused: RecorderError?
        var startedDuringFinish = false
        recorder.onTakeEnded = { [weak recorder] _ in
            guard let recorder else { return }
            finishingWhenTold.append(recorder.isFinishing)
            do {
                try recorder.startTake()
                startedDuringFinish = true
            } catch let error as RecorderError {
                refused = error
            } catch {}
        }
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))

        try recorder.startTake()
        #expect(!recorder.isFinishing)
        try recorder.stopTake()

        #expect(finishingWhenTold == [true])
        #expect(refused == .finishing)
        #expect(!startedDuringFinish)
        #expect(!recorder.isFinishing)
        #expect(!recorder.isRecording, "the refused start started nothing")
        try recorder.startTake()
        #expect(recorder.isRecording)
        try recorder.stopTake()
    }
}

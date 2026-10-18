import AudioIO
import Foundation
@testable import Recording
import Testing

/// Stop is `async` (#652, part A, A3a) but still finishes on the main actor: same result as before, and the finishing
/// guard holds from the start of Stop to the end of its publishing.
@MainActor
@Suite("Async Stop")
struct AsyncStopTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "AsyncStopTests-\(UUID().uuidString)")

    @Test("The Recorder takes the rule's answer as given, off in a Release build's default")
    func injectedRule() {
        #expect(Recorder(deviceFolder: root, destinationCheckInterval: nil, asyncStopAvailable: { true }).asyncStopAvailable)
        #expect(!Recorder(deviceFolder: root, destinationCheckInterval: nil, asyncStopAvailable: { false }).asyncStopAvailable)
        #expect(Recorder(deviceFolder: root, destinationCheckInterval: nil).asyncStopAvailable == AsyncStopAvailability.isAvailableInThisBuild)
    }

    @Test("Stop awaited ends a normal Take with its results published")
    func normalTake() async throws {
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        var ended: [TakeEnd] = []
        recorder.onTakeEnded = { ended.append($0) }
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 4_800), Array(repeating: 0.1, count: 4_800)])

        try await recorder.stopTake()

        #expect(!recorder.isRecording)
        #expect(!recorder.isFinishing)
        #expect(recorder.currentShow?.takeCount == 1)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped))
        #expect(ended == [TakeEnd(take: 1, reason: .stopped)])
        #expect(recorder.dropoutCount == 0)
        #expect(recorder.copies[.device] != nil)
    }

    @Test("A Take is refused while Stop is publishing, flag true until Stop returns, false after")
    func guardHolds() async throws {
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        var duringPublish: [Bool] = []
        var refused: RecorderError?
        recorder.onTakeEnded = { [weak recorder] _ in
            guard let recorder else { return }
            duringPublish.append(recorder.isFinishing)
            do { try recorder.startTake() } catch let error as RecorderError { refused = error } catch {}
        }
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))
        try recorder.startTake()
        #expect(!recorder.isFinishing)

        try await recorder.stopTake()

        #expect(duringPublish == [true])
        #expect(refused == .finishing)
        #expect(!recorder.isFinishing)
        #expect(!recorder.isRecording)
        try recorder.startTake()
        #expect(recorder.isRecording)
        try await recorder.stopTake()
    }
}

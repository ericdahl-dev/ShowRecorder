import AudioIO
import Foundation
@testable import Recording
import Testing

/// Whoever follows Takes hears each end as it happens, not on the next poll.
@MainActor
@Suite("Take end hook")
struct TakeEndHookTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "TakeEndHookTests-\(UUID().uuidString)")

    @Test("Every Take end is told to onTakeEnded as it happens, with its reason, after lastTakeEnd is set")
    func toldAsItHappens() throws {
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        var heard: [TakeEnd] = []
        var lastTakeEndWhenTold: [TakeEnd?] = []
        recorder.onTakeEnded = { [weak recorder] end in
            heard.append(end)
            lastTakeEndWhenTold.append(recorder?.lastTakeEnd)
        }
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))

        try recorder.startTake()
        try recorder.stopTake()
        try recorder.startTake()
        try recorder.restartInput(on: FakeAudioDevice(inputChannelCount: 2))

        let ends = [TakeEnd(take: 1, reason: .stopped), TakeEnd(take: 2, reason: .inputChanged)]
        #expect(heard == ends)
        #expect(lastTakeEndWhenTold == ends)
    }
}

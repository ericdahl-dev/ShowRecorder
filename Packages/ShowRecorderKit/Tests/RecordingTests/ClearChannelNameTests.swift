import Foundation
@testable import Recording
import Testing

/// Emptying a channel's name, from the meter or the Channel names page, takes the typed name off.
@MainActor
@Suite("Clearing a channel name")
struct ClearChannelNameTests {
    @Test("An empty or blank name clears the channel; any other text names it")
    func emptyClears() {
        let root = FileManager.default.temporaryDirectory.appending(path: "ClearChannelNameTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        recorder.updateChannelName("Kick", forChannel: 1)
        recorder.updateChannelName("Snare", forChannel: 2)
        #expect(recorder.channelNames == [1: "Kick", 2: "Snare"])

        recorder.updateChannelName("", forChannel: 1)
        recorder.updateChannelName("   ", forChannel: 2)
        #expect(recorder.channelNames.isEmpty)
    }
}

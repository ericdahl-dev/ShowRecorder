import AudioIO
import Foundation
import Testing

@testable import Recording

/// The channel names page: one row per USB Channel.
@MainActor
@Suite("Channel name list")
struct ChannelNameListTests {
    @Test("One row per channel, numbered from 1, showing the typed name; the hint is the Mixer's name or the USB default")
    func rows() {
        let rows = ChannelNameList.rows(channelCount: 3, mixerNames: [0: "Kick", 2: "Bass"], typed: [2: "Snare Top"])
        #expect(rows.map(\.number) == [1, 2, 3])
        #expect(rows.map(\.name) == ["", "Snare Top", ""])
        #expect(rows.map(\.hint) == ["Kick", "USB 02", "Bass"])
    }

    @Test("Clearing a row takes the typed name away for the Show's later Takes, in Show.json too")
    func clearingARow() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ChannelNameListTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        try recorder.stopTake()
        recorder.setChannelName("Bass", forChannel: 1)
        recorder.setChannelName("Keys", forChannel: 2)

        recorder.clearChannelName(forChannel: 1)

        #expect(recorder.channelNames == [2: "Keys"])
        #expect(ShowFile.read(from: root.appending(path: "2026-10-06 Show"))?.channelNames == ["2": "Keys"])
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "2026-10-06 Show/Take 02/01 USB 01.wav").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "2026-10-06 Show/Take 02/02 Keys.wav").path))
    }
}

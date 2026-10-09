import AudioIO
import Foundation
import Testing

@testable import Recording

/// Names typed before come back as chips; the last Show's names can be copied.
@MainActor
@Suite("Saved channel names")
struct SavedChannelNamesTests {
    let root: URL
    let defaults: UserDefaults
    let suite: String

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "SavedChannelNamesTests-\(UUID().uuidString)")
        suite = "SavedChannelNamesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    final class Clock: @unchecked Sendable { nonisolated(unsafe) var now: Date; init(_ now: Date) { self.now = now } }
    let clock = Clock(RecordingTakeTests.showDay)

    func recorder() -> Recorder {
        let clock = clock
        return Recorder(deviceFolder: root, now: { clock.now }, savedNames: defaults)
    }

    @Test("Typed names are remembered, newest first, one per name whatever the case, kept across launches; the built-in shortcut names are not saved")
    func remembered() {
        let recorder = recorder()
        recorder.setChannelName("Pastor Mike", forChannel: 1)
        recorder.setChannelName("Choir mic", forChannel: 2)
        recorder.setChannelName("Kick", forChannel: 3)
        recorder.setChannelName("Vox 2", forChannel: 4)
        recorder.setChannelName("pastor mike", forChannel: 5)

        #expect(recorder.savedChannelNames == ["pastor mike", "Choir mic"])
        #expect(self.recorder().savedChannelNames == ["pastor mike", "Choir mic"], "after a relaunch")
    }

    @Test("The list is capped, dropping the oldest")
    func capped() {
        let recorder = recorder()
        for n in 1...(SavedChannelNames.limit + 5) { recorder.setChannelName("Name \(n)", forChannel: 1) }
        #expect(recorder.savedChannelNames.count == SavedChannelNames.limit)
        #expect(recorder.savedChannelNames.first == "Name \(SavedChannelNames.limit + 5)")
        #expect(!recorder.savedChannelNames.contains("Name 1"))
    }

    @Test("Copy from last Show fills this Show's names from the previous Show, replacing any, and says how many; with no previous names it does nothing")
    func copyFromLastShow() async throws {
        let first = recorder()
        #expect(first.copyChannelNamesFromLastShow() == nil, "no Show at all")
        try first.startNewShow(name: "Friday", venue: "")
        first.setChannelName("Lead Vocal", forChannel: 1)
        first.setChannelName("Bass", forChannel: 2)
        clock.now = clock.now.addingTimeInterval(3600)
        try first.startNewShow(name: "Saturday", venue: "")
        #expect(first.channelNames.isEmpty)
        first.setChannelName("Keys", forChannel: 3)

        #expect(first.copyChannelNamesFromLastShow() == 2)

        #expect(first.channelNames == [1: "Lead Vocal", 2: "Bass"])
        #expect(ShowFile.read(from: root.appending(path: "2026-10-06 Saturday"))?.channelNames == ["1": "Lead Vocal", "2": "Bass"])
        #expect(ShowFile.read(from: root.appending(path: "2026-10-06 Friday"))?.channelNames == ["1": "Lead Vocal", "2": "Bass"], "the old Show is unchanged")

        clock.now = clock.now.addingTimeInterval(3600)
        try first.startNewShow(name: "Sunday", venue: "")
        #expect(first.copyChannelNamesFromLastShow() == 2, "the last Show is now Saturday, which has them")

        // A last Show with no names: nothing to copy, and this Show's own names stay.
        try FileManager.default.removeItem(at: root.appending(path: "2026-10-06 Friday"))
        clock.now = clock.now.addingTimeInterval(3600)
        let other = recorder()
        try other.startNewShow(name: "Empty", venue: "")
        clock.now = clock.now.addingTimeInterval(3600)
        try other.startNewShow(name: "After empty", venue: "")
        other.setChannelName("Mine", forChannel: 1)
        #expect(other.copyChannelNamesFromLastShow() == nil)
        #expect(other.channelNames == [1: "Mine"])
    }
}

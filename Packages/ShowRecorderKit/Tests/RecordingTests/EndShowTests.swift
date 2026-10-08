import AudioIO
import Foundation
import Testing

@testable import Recording

/// A Show ends when the operator ends it, or after 6 hours with no Take.
@MainActor
@Suite("End Show")
struct EndShowTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    /// The injected clock, moved by the tests.
    @MainActor final class Clock { var now = RecordingTakeTests.showDay }
    let clock = Clock()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "EndShowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func recorder() -> Recorder {
        let clock = clock
        return Recorder(deviceFolder: device, now: { MainActor.assumeIsolated { clock.now } })
    }

    func record(_ recorder: Recorder) throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.1, count: 480)])
        try recorder.stopTake()
        recorder.disarm()
    }

    @Test("End Show marks the Show ended in its files, and the next record starts a new Show")
    func endShow() throws {
        let recorder = recorder()
        try record(recorder)
        try recorder.endShow()
        #expect(recorder.currentShow == nil)
        #expect(ShowFile.read(from: device.appending(path: "2026-10-06 Show"))?.endedAt != nil)

        try record(recorder)
        #expect(recorder.currentShow?.name == "2026-10-06 Show 2")
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show 2/Take 01").path))
    }

    @Test("It can't end a Show while a Take is running")
    func refusedWhileRecording() throws {
        let recorder = recorder()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        #expect(throws: RecorderError.takeRunning) { try recorder.endShow() }
        #expect(recorder.currentShow?.name == "2026-10-06 Show")
        try recorder.stopTake()
        #expect(ShowFile.read(from: device.appending(path: "2026-10-06 Show"))?.endedAt == nil)
    }

    @Test("After 6 idle hours from the end of the last Take the next record starts a new Show; 5 h 59 min does not")
    func sixIdleHours() throws {
        let recorder = recorder()
        try record(recorder)
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(5 * 3600 + 59 * 60)
        try record(recorder)
        #expect(recorder.currentShow?.name == "2026-10-06 Show", "5 h 59 min later: the same Show")
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 02").path))

        clock.now = clock.now.addingTimeInterval(6 * 3600)
        try record(recorder)
        #expect(recorder.currentShow?.name == "2026-10-07 Show", "6 h after the last Take: a new Show, dated the new day")
        #expect(ShowFile.read(from: device.appending(path: "2026-10-06 Show"))?.endedAt != nil, "the idle Show is ended")
    }

    @Test("A Show with no Take yet counts its idle time from when it was created")
    func idleFromCreation() throws {
        let recorder = recorder()
        try recorder.startNewShow(name: "Gig", venue: "")
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(6 * 3600)
        try record(recorder)
        #expect(recorder.currentShow?.name == "2026-10-07 Show", "the empty Show was over after 6 hours")
    }

    @Test("After a relaunch the idle time still counts from the last Take, and the venue is kept")
    func idleAndVenueSurviveARelaunch() throws {
        let first = recorder()
        try first.startNewShow(name: "Gig", venue: "The Hall")
        try record(first)

        clock.now = RecordingTakeTests.showDay.addingTimeInterval(3 * 3600)
        let second = recorder()
        try record(second)
        #expect(second.currentShow?.name == "2026-10-06 Gig", "3 h later: still the same Show")
        let file = try #require(ShowFile.read(from: device.appending(path: "2026-10-06 Gig")))
        #expect(file.venue == "The Hall", "the venue isn't lost when the Show is found again")

        clock.now = clock.now.addingTimeInterval(6 * 3600)
        let third = recorder()
        try record(third)
        #expect(third.currentShow?.name == "2026-10-07 Show")
    }
}

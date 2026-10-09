import AudioIO
import Foundation
import Testing

@testable import Recording
@testable import ShowReport

/// A Show keeps the date it started, so a Take after midnight stays in the evening's Show.
@MainActor
@Suite("Show date")
struct ShowDateTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    @MainActor final class Clock { var now = RecordingTakeTests.showDay }
    let clock = Clock()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShowDateTests-\(UUID().uuidString)")
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

    /// 21:30 plus 2 h 50 min is 00:20 the next day.
    var afterMidnight: Date { RecordingTakeTests.showDay.addingTimeInterval(2 * 3600 + 50 * 60) }

    @Test("A Show started at 21:30 keeps its date: a Take at 00:20 lands in it, and Show.json keeps the start")
    func takeAfterMidnightStaysInShow() throws {
        let recorder = recorder()
        try record(recorder)
        clock.now = afterMidnight
        try record(recorder)

        #expect(recorder.currentShow?.name == "2026-10-06 Show")
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 02").path))
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: "2026-10-07 Show").path))
        #expect(ShowFile.read(from: device.appending(path: "2026-10-06 Show"))?.startedAt == RecordingTakeTests.showDay)
    }

    @Test("A relaunch after midnight finds the same Show, and its start date is still the evening before")
    func relaunchAfterMidnight() throws {
        try record(recorder())
        clock.now = afterMidnight
        let relaunched = recorder()
        #expect(relaunched.currentShow?.name == "2026-10-06 Show")
        try record(relaunched)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 02").path))
    }

    @Test("After End Show, the next evening's Show gets the new date")
    func nextEveningGetsNewDate() throws {
        let recorder = recorder()
        try record(recorder)
        try recorder.endShow()
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(recorder)
        #expect(recorder.currentShow?.name == "2026-10-07 Show")
        #expect(ShowFile.read(from: device.appending(path: "2026-10-07 Show"))?.startedAt == clock.now)
    }

    @Test("The report and the Reaper project name the Show by its start date, even for a Take after midnight")
    func reportAndProjectUseShowDate() throws {
        let recorder = recorder()
        try record(recorder)
        clock.now = afterMidnight
        try record(recorder)
        let folder = device.appending(path: "2026-10-06 Show")
        let report = try ShowReport(showFolder: folder)
        #expect(report.showName == "2026-10-06 Show")
        #expect(report.takes.map(\.number) == [1, 2])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "2026-10-06 Show.rpp").path))
    }
}

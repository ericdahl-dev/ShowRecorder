import AudioIO
import Destinations
import Foundation
import Testing

@testable import Recording

/// The open Show survives a crash or relaunch: it is written to `Show.json` and found again.
@MainActor
@Suite("Open Show")
struct ShowPersistenceTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShowPersistenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// A fresh recorder on the same folders, as after a relaunch.
    func launch(at now: Date = RecordingTakeTests.showDay, withDrive: Bool = false) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { withDrive ? DestinationAccess(folder: drive) : nil },
            now: { now })
    }

    func record(_ recorder: Recorder) throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.1, count: 480)])
        try recorder.stopTake()
        recorder.disarm()
    }

    @Test("After a relaunch the next Take lands in the same Show, numbered on from the last")
    func relaunchKeepsTheShow() throws {
        let first = launch()
        try record(first)
        #expect(first.currentShow?.name == "2026-10-06 Show")

        let second = launch()
        #expect(second.currentShow?.name == "2026-10-06 Show", "found again at launch")
        try record(second)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 02").path))
        #expect(!fm.fileExists(atPath: device.appending(path: "2026-10-06 Show 2").path), "no second Show")
    }

    @Test("Show.json is written in the Device Copy and the Drive Copy, with the name and the start")
    func showFileInBothCopies() throws {
        try record(launch(withDrive: true))
        for parent in [device, drive] {
            let file = try #require(ShowFile.read(from: parent.appending(path: "2026-10-06 Show")), "\(parent.lastPathComponent)")
            #expect(file.name == "2026-10-06 Show")
            #expect(abs(file.startedAt.timeIntervalSince(RecordingTakeTests.showDay)) < 1)
            #expect(file.endedAt == nil)
        }
    }

    @Test("With two Shows open, the newest is used and the older one is marked ended")
    func oneShowOpen() throws {
        let older = device.appending(path: "2026-10-04 Show")
        let newer = device.appending(path: "2026-10-05 Gig")
        for (folder, name, day) in [(older, "2026-10-04 Show", 4), (newer, "2026-10-05 Gig", 5)] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let start = RecordingTakeTests.showDay.addingTimeInterval(Double(day - 6) * 86_400)
            try ShowFile(name: name, startedAt: start, endedAt: nil).write(to: folder)
        }
        let recorder = launch()
        #expect(recorder.currentShow?.name == "2026-10-05 Gig")
        #expect(ShowFile.read(from: older)?.endedAt != nil)
        #expect(ShowFile.read(from: newer)?.endedAt == nil)
    }

    @Test("Shows with a broken or missing Show.json, and ended Shows, are never the open Show; recording still works")
    func ignoresWhatItCannotUse() throws {
        let fm = FileManager.default
        let broken = device.appending(path: "2026-10-01 Broken")
        let old = device.appending(path: "2026-10-02 Old")
        let ended = device.appending(path: "2026-10-03 Ended")
        for folder in [broken, old, ended] { try fm.createDirectory(at: folder.appending(path: "Take 01"), withIntermediateDirectories: true) }
        try Data("{ not json".utf8).write(to: broken.appending(path: "Show.json"))
        try ShowFile(name: "2026-10-03 Ended", startedAt: RecordingTakeTests.showDay, endedAt: RecordingTakeTests.showDay).write(to: ended)

        let recorder = launch()
        #expect(recorder.currentShow == nil)
        try record(recorder)
        #expect(recorder.currentShow?.name == "2026-10-06 Show", "a new Show, with Take 01")
        #expect(fm.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 01").path))
    }
}

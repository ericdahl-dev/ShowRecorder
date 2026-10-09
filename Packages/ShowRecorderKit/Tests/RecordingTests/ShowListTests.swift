import AudioIO
import Destinations
import Foundation
import Testing

@testable import Recording

/// The Show list: past Shows read from the files, newest first.
@MainActor
@Suite("Show list")
struct ShowListTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    @MainActor final class Clock { var now = RecordingTakeTests.showDay }
    let clock = Clock()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShowListTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorder(withDrive: Bool = false) -> Recorder {
        let clock = clock, drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { withDrive ? DestinationAccess(folder: drive) : nil },
            now: { MainActor.assumeIsolated { clock.now } })
    }

    func record(_ recorder: Recorder) throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.1, count: 480)])
        try recorder.stopTake()
        recorder.disarm()
    }

    @Test("Shows are listed newest first with their start, Take count and duration from first Take start to last Take end")
    func newestFirst() throws {
        let recorder = recorder()
        try record(recorder)
        clock.now = clock.now.addingTimeInterval(3600)
        try record(recorder)
        try recorder.endShow()
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(recorder)

        let shows = ShowList.read(device: device, drive: nil)
        #expect(shows.map(\.name) == ["2026-10-07 Show", "2026-10-06 Show"])
        #expect(shows.map(\.takeCount) == [1, 2])
        #expect(shows[1].startedAt == RecordingTakeTests.showDay)
        // Second Take starts 3600 s in and lasts 480 frames at 48 kHz (0.01 s).
        #expect(abs(shows[1].duration - 3600.01) < 0.001)
    }

    @Test("A Show on both Copies says complete for each; a Show on the Device only has no Drive Copy")
    func copyStates() throws {
        let both = recorder(withDrive: true)
        try record(both)
        try both.endShow()
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(recorder())

        let shows = ShowList.read(device: device, drive: drive)
        #expect(shows[1].deviceCopy == .complete)
        #expect(shows[1].driveCopy == .complete)
        #expect(shows[0].deviceCopy == .complete)
        #expect(shows[0].driveCopy == nil, "not there")
    }

    /// Rewrites a Take's Take.json in both Copies, as Repair leaves it.
    func edit(_ takeFolder: URL, _ change: (inout TakeMetadata) -> Void) throws {
        for folder in [takeFolder, drive.appending(path: takeFolder.deletingLastPathComponent().lastPathComponent).appending(path: takeFolder.lastPathComponent)] {
            try editOne(folder, change)
        }
    }

    func editOne(_ takeFolder: URL, _ change: (inout TakeMetadata) -> Void) throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        let url = takeFolder.appending(path: TakeMetadata.fileName)
        var take = try decoder.decode(TakeMetadata.self, from: Data(contentsOf: url))
        change(&take)
        try encoder.encode(take).write(to: url)
    }

    @Test("A Copy's state is the worst of its Takes: has Gaps, Repaired or Repair failed")
    func gapsAndRepairs() throws {
        let both = recorder(withDrive: true)
        try record(both)
        clock.now = clock.now.addingTimeInterval(60)
        try record(both)
        let take1 = device.appending(path: "2026-10-06 Show/Take 01")
        let take2 = device.appending(path: "2026-10-06 Show/Take 02")
        try edit(take1) { $0.gaps = [.init(copy: .drive, start: 0, end: 10)] }
        #expect(ShowList.read(device: device, drive: drive)[0].driveCopy == .hasGaps)
        #expect(ShowList.read(device: device, drive: drive)[0].deviceCopy == .complete)

        try edit(take1) { $0.repairs = [.init(copy: .drive, start: 0, end: 10, outcome: .repaired)] }
        #expect(ShowList.read(device: device, drive: drive)[0].driveCopy == .repaired)

        try edit(take2) {
            $0.gaps = [.init(copy: .drive, start: 0, end: 5)]
            $0.repairs = [.init(copy: .drive, start: 0, end: 5, outcome: .failed)]
        }
        #expect(ShowList.read(device: device, drive: drive)[0].driveCopy == .repairFailed)
    }

    @Test("An empty Show, a Show on the Drive only and an old Show with no Show.json all list without error")
    func oddShows() throws {
        let both = recorder(withDrive: true)
        try both.startNewShow(name: "Empty", venue: "")
        try both.endShow()

        // An old Show: Takes, but no Show.json on either Copy.
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(24 * 3600)
        try record(both)
        try both.endShow()
        for parent in [device, drive] {
            try FileManager.default.removeItem(at: parent.appending(path: "2026-10-07 Show/Show.json"))
        }

        // A Show only on the Drive: the Device Copy was lost.
        clock.now = RecordingTakeTests.showDay.addingTimeInterval(48 * 3600)
        try record(both)
        try FileManager.default.removeItem(at: device.appending(path: "2026-10-08 Show"))

        let shows = ShowList.read(device: device, drive: drive)
        #expect(shows.map(\.name) == ["2026-10-08 Show", "2026-10-07 Show", "2026-10-06 Empty"])
        #expect(shows[0].deviceCopy == nil)
        #expect(shows[0].driveCopy == .complete)
        #expect(shows[1].takeCount == 1)
        #expect(shows[1].startedAt == RecordingTakeTests.showDay.addingTimeInterval(24 * 3600), "from its first Take")
        #expect(shows[2].takeCount == 0)
        #expect(shows[2].duration == 0)
    }
}

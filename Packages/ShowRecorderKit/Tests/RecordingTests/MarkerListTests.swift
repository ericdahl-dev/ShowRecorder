import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

/// The Marker list the record screen shows, and renaming from it during and after a Take.
@MainActor
@Suite("Marker list")
struct MarkerListTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "MarkerListTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorder(drive available: Bool = true, released: Counter? = nil) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { available ? DestinationAccess(folder: drive, release: { released?.count += 1 }) : nil },
            now: { RecordingTakeTests.showDay })
    }

    final class Counter { var count = 0 }

    @Test("Each Marker is listed with its time in the Take, its name and its index among the operator's Markers")
    func listsMarkers() throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        #expect(recorder.markerEntries.isEmpty)
        audio.deliver([Array(repeating: 0, count: 4_800)])
        recorder.addMarker()
        audio.deliver([Array(repeating: 0, count: 2_400)])
        recorder.addMarker(named: "Chorus")

        #expect(recorder.markerEntries.map(\.name) == ["Marker 1", "Chorus"])
        #expect(recorder.markerEntries.map(\.seconds) == [0.1, 0.15])
        #expect(recorder.markerEntries.map(\.operatorIndex) == [0, 1])
        try recorder.stopTake()
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("A Dropout Marker is listed with no operator index, and doesn't shift the operator's Markers' indices")
    func dropoutInTheList() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0, count: 4_800)])
        audio.deliver([Array(repeating: 0, count: 300_000)])  // more than a ring holds: dropped
        audio.deliver([Array(repeating: 0, count: 480)])
        try await waitUntil { recorder.checkDestinations(); return recorder.dropoutCount == 1 }
        recorder.addMarker()

        #expect(recorder.markerEntries.map(\.name) == ["Dropout", "Marker 1"])
        #expect(recorder.markerEntries.map(\.operatorIndex) == [nil, 0])
        #expect(recorder.markerEntries.first?.isDropout == true)
        #expect(recorder.markerEntries.first?.seconds == 0.1)
        try recorder.stopTake()
    }

    @Test("A Dropout appears in the list as soon as the recorder notices it, not when the next Marker is placed")
    func dropoutAppearsWithoutAMarker() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0, count: 4_800)])
        audio.deliver([Array(repeating: 0, count: 300_000)])
        audio.deliver([Array(repeating: 0, count: 480)])
        try await waitUntil { recorder.checkDestinations(); return recorder.dropoutCount == 1 }

        #expect(recorder.markerEntries.map(\.name) == ["Dropout"])
        try recorder.stopTake()
    }

    @Test("The list stays after the Take, with a Dropout noticed only at the end, and clears when the next Take starts")
    func staysAfterTheTake() throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0, count: 4_800)])
        recorder.addMarker()
        audio.deliver([Array(repeating: 0, count: 300_000)])  // dropped, and nothing has looked since
        audio.deliver([Array(repeating: 0, count: 480)])
        try recorder.stopTake()

        #expect(recorder.markerEntries.map(\.name) == ["Marker 1", "Dropout"])
        try recorder.startTake()
        #expect(recorder.markerEntries.isEmpty)
        try recorder.stopTake()
    }

    func names(_ copy: URL) throws -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = try Data(contentsOf: copy.appending(path: "2026-10-06 Show/Take 01/Take.json"))
        return try decoder.decode(TakeMetadata.self, from: json).markers.map(\.name)
    }

    @Test("After the Take a Marker can be renamed in both Copies, with the Drive reached again for the rename and let go after")
    func renameAfterTheTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let released = Counter()
        let recorder = recorder(released: released)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0, count: 4_800)])
        recorder.addMarker()
        audio.deliver([Array(repeating: 0, count: 480)])
        try recorder.stopTake()
        await recorder.waitForRepair()
        let releasedBefore = released.count

        let outcome = await recorder.renameLastTakeMarker(at: 0, to: "Intro")

        #expect(outcome.result == .renamed)
        #expect(Set(outcome.renamed) == [.device, .drive])
        #expect(try names(device) == ["Intro"])
        #expect(try names(drive) == ["Intro"])
        #expect(recorder.markerEntries.map(\.name) == ["Intro"])
        #expect(recorder.takeMarkers.map(\.name) == ["Intro"])
        #expect(released.count == releasedBefore + 1, "the Drive access taken for the rename is let go")
    }

    @Test("With the Drive not there at rename time, the Device Copy is renamed and the outcome says the Drive wasn't")
    func driveAwayAtRenameTime() async throws {
        final class Flag: @unchecked Sendable { var available = true }
        let flag = Flag()
        let drive = drive
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { flag.available ? DestinationAccess(folder: drive) : nil },
            now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0, count: 4_800)])
        recorder.addMarker()
        try recorder.stopTake()
        await recorder.waitForRepair()
        flag.available = false

        let outcome = await recorder.renameLastTakeMarker(at: 0, to: "Intro")

        #expect(outcome.result == .renamed)
        #expect(outcome.renamed == [.device])
        #expect(outcome.failed.map(\.copy) == [.drive])
        #expect(try names(device) == ["Intro"])
        #expect(try names(drive) == ["Marker 1"], "the Drive Copy keeps the old name")
    }

    @Test("There is nothing to rename after a Take until one has been recorded, or while one is running")
    func nothingToRename() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        #expect(await recorder.renameLastTakeMarker(at: 0, to: "Intro").result == .notRecording)

        try recorder.startTake()
        audio.deliver([Array(repeating: 0, count: 480)])
        recorder.addMarker()
        #expect(await recorder.renameLastTakeMarker(at: 0, to: "Intro").result == .notRecording, "use renameMarker while recording")
        #expect(recorder.takeMarkers.map(\.name) == ["Marker 1"])
        try recorder.stopTake()
    }
}

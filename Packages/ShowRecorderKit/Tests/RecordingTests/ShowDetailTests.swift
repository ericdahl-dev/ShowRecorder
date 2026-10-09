import AudioIO
import Destinations
import Foundation
import Testing

@testable import Recording

/// The Show detail: a Show's Markers by Take, and renaming them from the files.
@MainActor
@Suite("Show detail")
struct ShowDetailTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    @MainActor final class Clock { var now = RecordingTakeTests.showDay }
    let clock = Clock()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShowDetailTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// Records a Take with `markers` operator Markers, 0.1 s apart from 0.1 s in.
    func record(_ recorder: Recorder, markers: Int) throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        for _ in 0..<markers {
            audio.deliver([Array(repeating: 0.1, count: 4_800)])
            recorder.addMarker()
        }
        audio.deliver([Array(repeating: 0.1, count: 480)])
        try recorder.stopTake()
        recorder.disarm()
    }

    func recorder() -> Recorder {
        let clock = clock, drive = drive
        return Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { MainActor.assumeIsolated { clock.now } })
    }

    @Test("Markers are listed by Take with their time in the Take; a Take with none lists none; a Dropout Marker has no rename index")
    func markersByTake() throws {
        let recorder = recorder()
        try record(recorder, markers: 2)
        try record(recorder, markers: 0)
        // Put a Dropout Marker between the operator's two, and take Take 2's Markers away as an old Take would have.
        let take1 = device.appending(path: "2026-10-06 Show/Take 01/Take.json")
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        var metadata = try decoder.decode(TakeMetadata.self, from: Data(contentsOf: take1))
        metadata.markers.insert(.init(position: 7_000, name: "Dropout", origin: .dropout), at: 1)
        try encoder.encode(metadata).write(to: take1)

        let takes = ShowDetail.read(showFolder: device.appending(path: "2026-10-06 Show"))
        #expect(takes.map(\.number) == [1, 2])
        #expect(takes[0].markers.map(\.name) == ["Marker 1", "Dropout", "Marker 2"])
        #expect(takes[0].markers.map(\.operatorIndex) == [0, nil, 1])
        #expect(takes[0].markers.map(\.seconds) == [0.1, 7_000.0 / 48_000, 0.2])
        #expect(takes[1].markers.isEmpty)
    }

    @Test("Renaming from the detail changes that Take's Marker in both Copies, and no other Take")
    func renameFromDetail() throws {
        let recorder = recorder()
        try record(recorder, markers: 2)
        try record(recorder, markers: 1)

        let outcome = ShowDetail.renameMarker(
            at: 1, to: "Encore", inTake: 1, ofShow: "2026-10-06 Show", device: device, drive: drive)

        #expect(outcome.result == .renamed)
        #expect(Set(outcome.renamed) == [.device, .drive])
        for parent in [device, drive] {
            let takes = ShowDetail.read(showFolder: parent.appending(path: "2026-10-06 Show"))
            #expect(takes[0].markers.map(\.name) == ["Marker 1", "Encore"])
            #expect(takes[1].markers.map(\.name) == ["Marker 1"])
        }
    }

    @Test("With no Drive, only the Device Copy is renamed and nothing is reported as failed")
    func renameWithoutDrive() throws {
        let recorder = recorder()
        try record(recorder, markers: 1)
        try FileManager.default.removeItem(at: drive.appending(path: "2026-10-06 Show"))

        let outcome = ShowDetail.renameMarker(at: 0, to: "Intro", inTake: 1, ofShow: "2026-10-06 Show", device: device, drive: nil)

        #expect(outcome.renamed == [.device])
        #expect(outcome.failed.isEmpty)
    }
}

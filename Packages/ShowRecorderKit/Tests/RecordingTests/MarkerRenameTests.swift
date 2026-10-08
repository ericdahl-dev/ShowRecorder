import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

@MainActor
@Suite("Renaming a Marker during a Take")
struct MarkerRenameTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "MarkerRenameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func deliver(_ audio: FakeAudioDevice, _ frames: Int) {
        audio.deliver(Array(repeating: Array(repeating: 0, count: frames), count: 2))
    }

    func recorder() -> Recorder {
        let drive = drive
        return Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
    }

    func names(inTakeJSONOf copy: URL) throws -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = try Data(contentsOf: copy.appending(path: "2026-10-06 Show/Take 01/Take.json"))
        return try decoder.decode(TakeMetadata.self, from: json).markers.map(\.name)
    }

    @Test("Renaming a Marker changes its name in Take.json and in every Stem's cue labels, in both Copies, and nothing else")
    func renameReachesEverything() throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        deliver(audio, 4_800)
        recorder.addMarker()
        deliver(audio, 2_400)
        recorder.addMarker()
        deliver(audio, 480)

        #expect(recorder.renameMarker(at: 1, to: "Chorus") == .renamed)
        #expect(recorder.takeMarkers.map(\.name) == ["Marker 1", "Chorus"])
        deliver(audio, 480)
        recorder.addMarker()
        #expect(recorder.takeMarkers.map(\.name) == ["Marker 1", "Chorus", "Marker 3"], "numbering carries on from the operator's Markers")
        try recorder.stopTake()

        let expected = [
            CuePoint(position: 4_800, label: "Marker 1"), CuePoint(position: 7_200, label: "Chorus"), CuePoint(position: 8_160, label: "Marker 3"),
        ]
        for copy in [device, drive] {
            #expect(try names(inTakeJSONOf: copy) == ["Marker 1", "Chorus", "Marker 3"])
            for stem in ["01 USB 01", "02 USB 02"] {
                #expect(try cuePoints(copy.appending(path: "2026-10-06 Show/Take 01/\(stem).wav")) == expected, "\(stem) in \(copy.lastPathComponent)")
            }
        }
    }

    @Test("A rename that can't be done says so and changes nothing: no Take, no such Marker, an empty name")
    func refusals() throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let recorder = recorder()
        try recorder.arm(audio)
        #expect(recorder.renameMarker(at: 0, to: "Chorus") == .notRecording)

        try recorder.startTake()
        deliver(audio, 480)
        recorder.addMarker()
        #expect(recorder.renameMarker(at: 1, to: "Chorus") == .noSuchMarker)
        #expect(recorder.renameMarker(at: -1, to: "Chorus") == .noSuchMarker)
        #expect(recorder.renameMarker(at: 0, to: "") == .emptyName)
        #expect(recorder.renameMarker(at: 0, to: "  \n ") == .emptyName)
        #expect(recorder.takeMarkers.map(\.name) == ["Marker 1"])
        try recorder.stopTake()
    }
}

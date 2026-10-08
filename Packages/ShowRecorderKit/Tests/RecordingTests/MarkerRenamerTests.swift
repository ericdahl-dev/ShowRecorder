import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

/// Renaming a Marker after the Take, from the files on disk.
@MainActor
@Suite("Renaming a Marker from files")
struct MarkerRenamerTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    func take(_ copy: URL) -> URL { copy.appending(path: "2026-10-06 Show/Take 01") }
    var copies: [DestinationKind: URL] { [.device: take(device), .drive: take(drive)] }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "MarkerRenamerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// Records a Take in both Copies: audio, Marker 1 at 4,800 and Marker 2 at 7,200.
    func recordTake() throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake()
        func deliver(_ frames: Int) {
            audio.deliver((0..<2).map { channel in (0..<frames).map { Float($0 % 1000 + channel * 1000) / 8_388_608 } })
        }
        deliver(4_800)
        recorder.addMarker()
        deliver(2_400)
        recorder.addMarker()
        deliver(480)
        try recorder.stopTake()
    }

    func markerNames(_ copy: URL) throws -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: Data(contentsOf: copy.appending(path: "Take.json"))).markers.map(\.name)
    }

    @Test("Renaming changes Take.json and every Stem's cue label in both Copies, and leaves the audio exactly as it was")
    func renameOnDisk() throws {
        try recordTake()
        let stems = ["01 USB 01.wav", "02 USB 02.wav"]
        let before = try copies.values.flatMap { copy in try stems.map { try StemFile(contentsOf: copy.appending(path: $0)) } }

        let outcome = MarkerRenamer.rename(markerAt: 1, to: "Chorus", in: copies)

        #expect(outcome.result == .renamed)
        #expect(Set(outcome.renamed) == [.device, .drive])
        #expect(outcome.failed.isEmpty)
        let expected = [CuePoint(position: 4_800, label: "Marker 1"), CuePoint(position: 7_200, label: "Chorus")]
        for copy in copies.values {
            #expect(try markerNames(copy) == ["Marker 1", "Chorus"])
            for stem in stems { #expect(try cuePoints(copy.appending(path: stem)) == expected, "\(stem)") }
        }
        let after = try copies.values.flatMap { copy in try stems.map { try StemFile(contentsOf: copy.appending(path: $0)) } }
        #expect(after.map(\.samples) == before.map(\.samples), "the audio is untouched")
        #expect(after.map(\.timeReference) == before.map(\.timeReference))
    }

    @Test("With a Copy not reachable, the others are renamed and the outcome names the Copy that wasn't")
    func oneCopyMissing() throws {
        try recordTake()
        try FileManager.default.moveItem(at: drive, to: root.appending(path: "Drive (unplugged)"))

        let outcome = MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies)

        #expect(outcome.result == .renamed)
        #expect(outcome.renamed == [.device])
        #expect(outcome.failed.map(\.copy) == [.drive])
        #expect(try markerNames(take(device)) == ["Intro", "Marker 2"])
        // Brought back, the Drive Copy still has the old name until the next rename.
        try FileManager.default.moveItem(at: root.appending(path: "Drive (unplugged)"), to: drive)
        #expect(try markerNames(take(drive)) == ["Marker 1", "Marker 2"])
    }

    @Test("The Show's report and Reaper project show the new name in every reachable Copy")
    func reportAndProjectFollow() throws {
        try recordTake()
        let show = "2026-10-06 Show"
        for copy in [device, drive] {
            let html = try String(contentsOf: copy.appending(path: "\(show)/Report.html"), encoding: .utf8)
            #expect(html.contains("Marker 2"))
        }

        _ = MarkerRenamer.rename(markerAt: 1, to: "Chorus", in: copies)

        for copy in [device, drive] {
            let html = try String(contentsOf: copy.appending(path: "\(show)/Report.html"), encoding: .utf8)
            #expect(html.contains("Chorus") && !html.contains("Marker 2"), "report in \(copy.lastPathComponent)")
            let project = try String(contentsOf: copy.appending(path: "\(show)/\(show).RPP"), encoding: .utf8)
            #expect(project.contains("Chorus") && !project.contains("Marker 2"), "project in \(copy.lastPathComponent)")
        }
    }

    @Test("An empty name or a Marker that isn't there changes nothing, and says which")
    func refusals() throws {
        try recordTake()
        let before = try Data(contentsOf: take(device).appending(path: "Take.json"))

        #expect(MarkerRenamer.rename(markerAt: 0, to: "   ", in: copies).result == .emptyName)
        let missing = MarkerRenamer.rename(markerAt: 5, to: "Chorus", in: copies)
        #expect(missing.result == .noSuchMarker)
        #expect(missing.renamed.isEmpty)
        #expect(try Data(contentsOf: take(device).appending(path: "Take.json")) == before)
    }

    @Test("With no Copy reachable, nothing is renamed and the result isn't mistaken for a missing Marker")
    func noCopyReachable() throws {
        try recordTake()
        let gone = ["Device", "Drive"].map { root.appending(path: $0) }
        for folder in gone { try FileManager.default.moveItem(at: folder, to: root.appending(path: "\(folder.lastPathComponent) away")) }

        let outcome = MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies)
        #expect(outcome.result == .noCopyUpdated)
        #expect(outcome.failed.count == 2)
    }

    @Test("A Copy's Dropout cues, and its other Markers' positions, survive a rename")
    func dropoutCuesSurvive() throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0, count: 4_800)])
        recorder.addMarker()
        audio.deliver([Array(repeating: 0, count: 300_000)])  // more than a ring holds: dropped in both Copies
        audio.deliver([Array(repeating: 0, count: 480)])
        try recorder.stopTake()
        let before = try cuePoints(take(device).appending(path: "01 USB 01.wav"))
        #expect(before.map(\.label).sorted() == ["Dropout", "Marker 1"])

        #expect(MarkerRenamer.rename(markerAt: 0, to: "Verse", in: copies).result == .renamed)

        for copy in copies.values {
            let cues = try cuePoints(copy.appending(path: "01 USB 01.wav"))
            #expect(cues.map(\.label).sorted() == ["Dropout", "Verse"], "\(copy.path)")
            #expect(cues.map(\.position).sorted() == before.map(\.position).sorted())
        }
    }

    @Test("A Stem that can't be opened is reported by name, and the other Stems and the other Copy are still renamed")
    func badStemIsReported() throws {
        try recordTake()
        try Data("not a stem".utf8).write(to: take(device).appending(path: "01 USB 01.wav"))

        let outcome = MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies)

        #expect(outcome.result == .renamed, "the Drive Copy was renamed")
        #expect(outcome.renamed == [.drive])
        #expect(outcome.failed.map(\.copy) == [.device])
        #expect(outcome.failed.first?.reason.contains("01 USB 01.wav") == true)
        // The Device Copy's good Stem and its Take.json were still done.
        #expect(try cuePoints(take(device).appending(path: "02 USB 02.wav")).first?.label == "Intro")
        #expect(try markerNames(take(device)) == ["Intro", "Marker 2"])
    }

    @Test("Renaming the same Marker again, or to the name it already has, works")
    func renameAgain() throws {
        try recordTake()
        #expect(MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies).result == .renamed)
        #expect(MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies).result == .renamed)
        #expect(MarkerRenamer.rename(markerAt: 0, to: "Verse", in: copies).result == .renamed)
        #expect(try markerNames(take(drive)) == ["Verse", "Marker 2"])
    }
}

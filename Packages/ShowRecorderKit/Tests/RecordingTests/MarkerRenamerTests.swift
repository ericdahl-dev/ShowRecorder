import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
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
    func recordTake(allowance: TakeAllowance? = nil) async throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake(allowance: allowance)
        let sample = { (frame: Int, channel: Int) in RecordingTakeTests.sample(Int32(frame % 1000 + channel * 1000)) }
        deliver(4_800, to: audio, sample: sample)
        recorder.addMarker()
        deliver(2_400, to: audio, sample: sample)
        recorder.addMarker()
        deliver(480, to: audio, sample: sample)
        try await recorder.stopTake()
    }

    func markerNames(_ copy: URL) throws -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: Data(contentsOf: copy.appending(path: "Take.json"))).markers.map(\.name)
    }

    @Test("Renaming changes Take.json and every Stem's cue label in both Copies, and leaves the audio exactly as it was")
    func renameOnDisk() async throws {
        try await recordTake()
        let stems = ["01 USB 01.wav", "02 USB 02.wav"]
        let before = try copies.values.flatMap { copy in try stems.map { try ParsedStem(contentsOf: copy.appending(path: $0)) } }

        let outcome = MarkerRenamer.rename(markerAt: 1, to: "Chorus", in: copies, allowsProExtras: true)

        #expect(outcome.result == .renamed)
        #expect(Set(outcome.renamed) == [.device, .drive])
        #expect(outcome.failed.isEmpty)
        let expected = [CuePoint(position: 4_800, label: "Marker 1"), CuePoint(position: 7_200, label: "Chorus")]
        for copy in copies.values {
            #expect(try markerNames(copy) == ["Marker 1", "Chorus"])
            for stem in stems { #expect(try cuePoints(copy.appending(path: stem)) == expected, "\(stem)") }
        }
        let after = try copies.values.flatMap { copy in try stems.map { try ParsedStem(contentsOf: copy.appending(path: $0)) } }
        #expect(after.map(\.samples) == before.map(\.samples), "the audio is untouched")
        #expect(after.map(\.timeReference) == before.map(\.timeReference))
    }

    @Test("A Stem another program re-saved is left as it is, and the outcome names it (#881)")
    func resavedStemIsLeftAlone() async throws {
        try await recordTake()
        let stem = take(device).appending(path: "02 USB 02.wav")
        var bytes = [UInt8](try Data(contentsOf: stem))
        bytes.insert(contentsOf: Array("JUNK".utf8) + [32, 0, 0, 0] + [UInt8](repeating: 0, count: 32), at: StemWriter.dataStart - 8)
        try Data(bytes).write(to: stem)
        let before = try Data(contentsOf: stem)

        let outcome = MarkerRenamer.rename(markerAt: 1, to: "Chorus", in: [.device: take(device)], allowsProExtras: true)

        #expect(outcome.failed.map(\.copy) == [.device])
        #expect(outcome.failed.first?.reason.contains("02 USB 02.wav") == true, "\(outcome.failed)")
        #expect(try Data(contentsOf: stem) == before)
    }

    @Test("With a Copy not reachable, the others are renamed and the outcome names the Copy that wasn't")
    func oneCopyMissing() async throws {
        try await recordTake()
        try FileManager.default.moveItem(at: drive, to: root.appending(path: "Drive (unplugged)"))

        let outcome = MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies, allowsProExtras: true)

        #expect(outcome.result == .renamed)
        #expect(outcome.renamed == [.device])
        #expect(outcome.failed.map(\.copy) == [.drive])
        #expect(try markerNames(take(device)) == ["Intro", "Marker 2"])
        // Brought back, the Drive Copy still has the old name until the next rename.
        try FileManager.default.moveItem(at: root.appending(path: "Drive (unplugged)"), to: drive)
        #expect(try markerNames(take(drive)) == ["Marker 1", "Marker 2"])
    }

    @Test("The Show's report and Reaper project show the new name in every reachable Copy")
    func reportAndProjectFollow() async throws {
        try await recordTake()
        let show = "2026-10-06 Show"
        for copy in [device, drive] {
            let html = try String(contentsOf: copy.appending(path: "\(show)/Report.html"), encoding: .utf8)
            #expect(html.contains("Marker 2"))
        }

        _ = MarkerRenamer.rename(markerAt: 1, to: "Chorus", in: copies, allowsProExtras: true)

        for copy in [device, drive] {
            let html = try String(contentsOf: copy.appending(path: "\(show)/Report.html"), encoding: .utf8)
            #expect(html.contains("Chorus") && !html.contains("Marker 2"), "report in \(copy.lastPathComponent)")
            let project = try String(contentsOf: copy.appending(path: "\(show)/\(show).RPP"), encoding: .utf8)
            #expect(project.contains("Chorus") && !project.contains("Marker 2"), "project in \(copy.lastPathComponent)")
        }
    }

    @Test("On Free a rename writes no Show report or Reaper project that wasn't there (#438)")
    func freeWritesNoExtras() async throws {
        try await recordTake(allowance: Entitlement.allowance(for: .free, channelCount: 2))
        let show = "2026-10-06 Show"
        #expect(MarkerRenamer.rename(markerAt: 1, to: "Chorus", in: copies, allowsProExtras: false).result == .renamed)
        for copy in [device, drive] {
            #expect(!FileManager.default.fileExists(atPath: copy.appending(path: "\(show)/Report.html").path))
            #expect(!FileManager.default.fileExists(atPath: copy.appending(path: "\(show)/\(show).RPP").path))
        }
    }

    @Test("On Free a report and project already there (from a Trial) still get the new name (#438)")
    func freeKeepsExistingExtrasCurrent() async throws {
        try await recordTake()
        let show = "2026-10-06 Show"
        _ = MarkerRenamer.rename(markerAt: 1, to: "Chorus", in: copies, allowsProExtras: false)
        for copy in [device, drive] {
            #expect(try String(contentsOf: copy.appending(path: "\(show)/Report.html"), encoding: .utf8).contains("Chorus"))
            #expect(try String(contentsOf: copy.appending(path: "\(show)/\(show).RPP"), encoding: .utf8).contains("Chorus"))
        }
    }

    @Test("An empty name or a Marker that isn't there changes nothing, and says which")
    func refusals() async throws {
        try await recordTake()
        let before = try Data(contentsOf: take(device).appending(path: "Take.json"))

        #expect(MarkerRenamer.rename(markerAt: 0, to: "   ", in: copies, allowsProExtras: true).result == .emptyName)
        let missing = MarkerRenamer.rename(markerAt: 5, to: "Chorus", in: copies, allowsProExtras: true)
        #expect(missing.result == .noSuchMarker)
        #expect(missing.renamed.isEmpty)
        #expect(try Data(contentsOf: take(device).appending(path: "Take.json")) == before)
    }

    @Test("With no Copy reachable, nothing is renamed and the result isn't mistaken for a missing Marker")
    func noCopyReachable() async throws {
        try await recordTake()
        let gone = ["Device", "Drive"].map { root.appending(path: $0) }
        for folder in gone { try FileManager.default.moveItem(at: folder, to: root.appending(path: "\(folder.lastPathComponent) away")) }

        let outcome = MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies, allowsProExtras: true)
        #expect(outcome.result == .noCopyUpdated)
        #expect(outcome.failed.count == 2)
    }

    @Test("A Copy's Dropout cues, and its other Markers' positions, survive a rename")
    func dropoutCuesSurvive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0, count: 4_800)])
        recorder.addMarker()
        audio.deliver([Array(repeating: 0, count: 300_000)])  // more than a ring holds: dropped in both Copies
        audio.deliver([Array(repeating: 0, count: 480)])
        try await recorder.stopTake()
        let before = try cuePoints(take(device).appending(path: "01 USB 01.wav"))
        #expect(before.map(\.label).sorted() == ["Dropout", "Marker 1"])

        #expect(MarkerRenamer.rename(markerAt: 0, to: "Verse", in: copies, allowsProExtras: true).result == .renamed)

        for copy in copies.values {
            let cues = try cuePoints(copy.appending(path: "01 USB 01.wav"))
            #expect(cues.map(\.label).sorted() == ["Dropout", "Verse"], "\(copy.path)")
            #expect(cues.map(\.position).sorted() == before.map(\.position).sorted())
        }
    }

    @Test("A Stem that can't be opened is reported by name, and the other Stems and the other Copy are still renamed")
    func badStemIsReported() async throws {
        try await recordTake()
        try Data("not a stem".utf8).write(to: take(device).appending(path: "01 USB 01.wav"))

        let outcome = MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies, allowsProExtras: true)

        #expect(outcome.result == .renamed, "the Drive Copy was renamed")
        #expect(outcome.renamed == [.drive])
        #expect(outcome.failed.map(\.copy) == [.device])
        #expect(outcome.failed.first?.reason.contains("01 USB 01.wav") == true)
        // The Device Copy's good Stem and its Take.json were still done.
        #expect(try cuePoints(take(device).appending(path: "02 USB 02.wav")).first?.label == "Intro")
        #expect(try markerNames(take(device)) == ["Intro", "Marker 2"])
    }

    @Test("Renaming the same Marker again, or to the name it already has, works")
    func renameAgain() async throws {
        try await recordTake()
        #expect(MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies, allowsProExtras: true).result == .renamed)
        #expect(MarkerRenamer.rename(markerAt: 0, to: "Intro", in: copies, allowsProExtras: true).result == .renamed)
        #expect(MarkerRenamer.rename(markerAt: 0, to: "Verse", in: copies, allowsProExtras: true).result == .renamed)
        #expect(try markerNames(take(drive)) == ["Verse", "Marker 2"])
    }

    @Test("In a stand-in kept on the Device, a renamed Marker's cue counts from the stand-in's start, and earlier ones stay out (#622)")
    func standInCuesShifted() async throws {
        try await recordTake()
        // Markers at 2,400 and 7,200; the Device stood in from 4,800 and kept its Stems in the stand-in's folder.
        for copy in copies.values {
            var metadata = try TakeMetadata.read(fromTakeFolder: copy)
            metadata.markers[0].position = 2_400
            try metadata.write(to: copy)
        }
        var deviceTake = try TakeMetadata.read(fromTakeFolder: take(device))
        let standIn = TakeMetadata.StandIn(start: 4_800, end: 7_680)
        deviceTake.standIns = [standIn]
        try deviceTake.write(to: take(device))
        let standInFolder = take(device).appending(path: standIn.folderName)
        try FileManager.default.createDirectory(at: standInFolder, withIntermediateDirectories: true)
        let stems = ["01 USB 01.wav", "02 USB 02.wav"]
        for stem in stems { try FileManager.default.moveItem(at: take(device).appending(path: stem), to: standInFolder.appending(path: stem)) }

        let outcome = MarkerRenamer.rename(markerAt: 1, to: "Chorus", in: copies, allowsProExtras: true)

        #expect(Set(outcome.renamed) == [.device, .drive])
        #expect(outcome.failed.isEmpty)
        for stem in stems {
            #expect(try cuePoints(standInFolder.appending(path: stem)) == [CuePoint(position: 2_400, label: "Chorus")], "\(stem)")
            #expect(try cuePoints(take(drive).appending(path: stem))
                == [CuePoint(position: 2_400, label: "Marker 1"), CuePoint(position: 7_200, label: "Chorus")], "\(stem)")
        }
    }
}

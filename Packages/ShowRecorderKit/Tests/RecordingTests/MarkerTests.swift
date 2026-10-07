import AudioIO
import Foundation
@testable import Recording
import Testing

@MainActor
@Suite("Markers")
struct MarkerTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "MarkerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func deliver(_ audio: FakeAudioDevice, frames: Int, channels: Int) {
        audio.deliver(Array(repeating: Array(repeating: 0, count: frames), count: channels))
    }

    @Test("A Marker lands at the Take's current sample position in every Stem of both Copies and in Take.json")
    func markerAtCurrentPosition() throws {
        let audio = FakeAudioDevice(inputChannelCount: 3)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)

        try recorder.startTake()
        deliver(audio, frames: 4_800, channels: 3)
        recorder.addMarker()
        deliver(audio, frames: 2_400, channels: 3)
        recorder.addMarker(named: "Bridge")
        deliver(audio, frames: 100, channels: 3)
        try recorder.stopTake()

        let expected = [CuePoint(position: 4_800, label: "Marker 1"), CuePoint(position: 7_200, label: "Bridge")]
        for copy in [device, drive] {
            let take = copy.appending(path: "2026-10-06 Show/Take 01")
            for stem in ["01 USB 01", "02 USB 02", "03 USB 03"] {
                #expect(try cuePoints(take.appending(path: "\(stem).wav")) == expected, "\(stem) in \(copy.lastPathComponent)")
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadata = try decoder.decode(TakeMetadata.self, from: Data(contentsOf: take.appending(path: "Take.json")))
            #expect(metadata.markers == [
                TakeMetadata.Marker(position: 4_800, name: "Marker 1", origin: .operator),
                TakeMetadata.Marker(position: 7_200, name: "Bridge", origin: .operator),
            ])
        }
        #expect(recorder.takeMarkers.map(\.name) == ["Marker 1", "Bridge"])
    }

    @Test("Adding a Marker when not recording does nothing")
    func markerOutsideTakeIgnored() throws {
        let recorder = Recorder(deviceFolder: device, now: { RecordingTakeTests.showDay })
        try recorder.arm(FakeAudioDevice(inputChannelCount: 1))

        recorder.addMarker()

        #expect(recorder.takeMarkers.isEmpty)
    }

    @Test("Each Take starts with no Markers, and numbering restarts")
    func markersResetPerTake() throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake()
        recorder.addMarker()
        try recorder.stopTake()

        try recorder.startTake()
        deliver(audio, frames: 10, channels: 1)
        recorder.addMarker()
        try recorder.stopTake()

        #expect(recorder.takeMarkers == [TakeMetadata.Marker(position: 10, name: "Marker 1", origin: .operator)])
    }
}

extension MarkerTests {
    /// Records two one-second Takes with a Marker half a second into the second.
    func recordTwoTakesWithMarker(named name: String) throws -> URL {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake()
        deliver(audio, frames: 48_000, channels: 1)
        try recorder.stopTake()
        try recorder.startTake()
        deliver(audio, frames: 24_000, channels: 1)
        recorder.addMarker(named: name)
        deliver(audio, frames: 24_000, channels: 1)
        try recorder.stopTake()
        return device.appending(path: "2026-10-06 Show")
    }

    @Test("Markers appear on the Reaper timeline at their Take's start plus their position")
    func markersInReaperProject() throws {
        let show = try recordTwoTakesWithMarker(named: "Encore")

        let rpp = try String(contentsOf: show.appending(path: "2026-10-06 Show.RPP"), encoding: .utf8)
        let markerLines = rpp.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("MARKER ") && $0.contains("Encore") }
        #expect(markerLines.count == 1)
        let fields = markerLines.first.map { $0.split(separator: " ").map(String.init) } ?? []
        #expect(fields.count > 2 && Double(fields[2]) == 1.5, "Take 02 starts at 1 s; the Marker is 0.5 s in: \(fields)")
    }

    @Test("The Show report lists each Take's Markers with their time, names escaped")
    func markersInReport() throws {
        let show = try recordTwoTakesWithMarker(named: "<Solo> & Out")

        let html = try String(contentsOf: show.appending(path: "Report.html"), encoding: .utf8)
        #expect(html.contains("&lt;Solo&gt; &amp; Out"))
        #expect(!html.contains("<Solo>"))
        #expect(html.contains("0:00.5") || html.contains("0:00.500"), "the Marker's time in the Take")
    }
}

struct CuePoint: Equatable {
    var position: UInt32
    var label: String
}

/// Cue points and labels from the chunks before a Stem's audio.
func cuePoints(_ url: URL) throws -> [CuePoint] {
    let data = [UInt8](try Data(contentsOf: url))
    func u32(_ i: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(data[i + $1]) << (8 * $1) } }
    func id(_ i: Int) -> String { String(decoding: data[i..<i + 4], as: UTF8.self) }
    var positions: [UInt32: UInt32] = [:]
    var labels: [UInt32: String] = [:]
    var offset = 12
    while offset + 8 <= data.count, id(offset) != "data" {
        let size = Int(u32(offset + 4))
        let body = offset + 8
        if id(offset) == "cue " {
            for n in 0..<Int(u32(body)) { positions[u32(body + 4 + n * 24)] = u32(body + 4 + n * 24 + 20) }
        } else if id(offset) == "LIST", id(body) == "adtl" {
            var sub = body + 4
            while sub + 8 <= body + size {
                let subSize = Int(u32(sub + 4))
                if id(sub) == "labl" {
                    labels[u32(sub + 8)] = String(decoding: data[(sub + 12)..<(sub + 8 + subSize)].prefix { $0 != 0 }, as: UTF8.self)
                }
                sub += 8 + subSize + (subSize % 2)
            }
        }
        offset = body + size + (size % 2)
    }
    return positions.keys.sorted().map { CuePoint(position: positions[$0]!, label: labels[$0] ?? "") }
}

import AVFoundation
@testable import BroadcastWave
import Foundation
import Testing

@Suite("Markers in Stems")
struct StemMarkerTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "StemMarkerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static let info = StemWriter.Info(sampleRate: 48_000, description: "Kick", originator: "ShowRecorder", timeReference: 0, originationDate: .now)
    static func samples(_ range: Range<Int>) -> [Float] { range.map { Float($0 % 100_000) / 8_388_608 } }

    static func readAudio(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0 else { return [] }
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    @Test("Markers are written as cue points with labels, and the audio still reads back exactly")
    func markersAsCuePoints() throws {
        let url = folder.appending(path: "01 Kick.wav")
        let writer = try StemWriter(url: url, info: Self.info)
        let audio = Self.samples(0..<10_000)
        try audio.withUnsafeBufferPointer { try writer.append($0) }
        try writer.setMarkers([StemMarker(position: 480, label: "Song 1"), StemMarker(position: 9_000, label: "Bridge")])
        try writer.finalize()

        #expect(try CuePoints(contentsOf: url).points == [.init(position: 480, label: "Song 1"), .init(position: 9_000, label: "Bridge")])
        #expect(try Self.readAudio(url) == audio)
    }

    @Test("Markers set before a header commit survive a Take cut off after it")
    func markersSurviveCutOff() throws {
        let url = folder.appending(path: "cut.wav")
        let writer = try StemWriter(url: url, info: Self.info)
        try Self.samples(0..<5_000).withUnsafeBufferPointer { try writer.append($0) }
        try writer.setMarkers([StemMarker(position: 1_234, label: "Downbeat")])
        try writer.commitHeader()
        try Self.samples(5_000..<8_000).withUnsafeBufferPointer { try writer.append($0) }
        // The app dies here: no finalize.

        #expect(try CuePoints(contentsOf: url).points == [.init(position: 1_234, label: "Downbeat")])
        #expect(try Self.readAudio(url) == Self.samples(0..<5_000))
    }

    @Test("More Markers than the region holds: as many as fit, oldest first, and the file stays valid")
    func tooManyMarkers() throws {
        let url = folder.appending(path: "many.wav")
        let writer = try StemWriter(url: url, info: Self.info)
        try Self.samples(0..<1_000).withUnsafeBufferPointer { try writer.append($0) }
        let markers = (0..<2_000).map { StemMarker(position: UInt32($0), label: "Marker \($0 + 1)") }

        let fitted = try writer.setMarkers(markers)
        try writer.finalize()

        #expect(fitted > 100 && fitted < 2_000)
        #expect(try CuePoints(contentsOf: url).points.map(\.label) == markers.prefix(fitted).map(\.label))
        #expect(try Self.readAudio(url) == Self.samples(0..<1_000))
    }

    @Test("Replacing Markers removes ones taken out")
    func replacingMarkers() throws {
        let url = folder.appending(path: "replace.wav")
        let writer = try StemWriter(url: url, info: Self.info)
        try writer.setMarkers([StemMarker(position: 1, label: "A"), StemMarker(position: 2, label: "B")])
        try writer.setMarkers([StemMarker(position: 3, label: "C")])
        try writer.finalize()

        #expect(try CuePoints(contentsOf: url).points == [.init(position: 3, label: "C")])
    }
}

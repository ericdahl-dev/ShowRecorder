@testable import BroadcastWave
import Foundation
import Testing

/// A stereo pair's two lanes (#1088): the Take writer feeds them like two mono Stems, one USB Channel each, and they write
/// one interleaved stereo Stem. Built around a pair so a mixer whose USB sends are all pairs (Pioneer DJM, #364) can reuse it.
@Suite("Stereo pair lanes")
struct StereoPairTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "StereoPairTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static let info = StereoStemTests.info

    static func left(_ range: Range<Int>) -> [Float] { range.map { Float($0 % 100_000) / 8_388_608 } }
    static func right(_ range: Range<Int>) -> [Float] { range.map { -Float($0 % 100_000) / 8_388_608 } }

    func makeLanes(_ name: String) throws -> (url: URL, left: any StemSink, right: any StemSink) {
        let url = folder.appending(path: name)
        let lanes = StereoPair.lanes(writingTo: try StemWriter(url: url, info: Self.info))
        return (url, lanes.left, lanes.right)
    }

    @Test("Blocks fed left then right, as the Take writer drains its ring, become one interleaved stereo Stem")
    func interleaves() throws {
        let (url, left, right) = try makeLanes("pair.wav")
        for start in stride(from: 0, to: 10_000, by: 4_096) {
            let block = start..<min(start + 4_096, 10_000)
            try Self.left(block).withUnsafeBufferPointer { try left.append($0) }
            try Self.right(block).withUnsafeBufferPointer { try right.append($0) }
            try left.commitHeader()
            try right.commitHeader()
        }
        #expect(left.frameCount == 10_000)
        #expect(right.frameCount == 10_000)
        try left.finalize()
        try right.finalize()
        let stem = try StemFile.inspect(url)
        #expect(stem.channelCount == 2)
        #expect(stem.frameCount == 10_000)
        #expect(try StemWriter.readSamples(url: url, frames: 0..<10_000) == StereoStemTests.frames(0..<10_000))
    }

    @Test("A lane fed ahead of the other waits for it: each lane counts what it was given, the file only whole frames")
    func laneAhead() throws {
        let (url, left, right) = try makeLanes("ahead.wav")
        try Self.left(0..<3_000).withUnsafeBufferPointer { try left.append($0) }
        #expect(left.frameCount == 3_000)
        #expect(right.frameCount == 0)
        try Self.right(0..<1_000).withUnsafeBufferPointer { try right.append($0) }
        #expect(left.frameCount == 3_000)
        #expect(right.frameCount == 1_000)
        try Self.right(1_000..<3_000).withUnsafeBufferPointer { try right.append($0) }
        try left.finalize()
        try right.finalize()
        #expect(try StemWriter.readSamples(url: url, frames: 0..<3_000) == StereoStemTests.frames(0..<3_000))
    }

    @Test("A pair finalized with one lane ahead loses none of its audio: the other channel is silence there")
    func finalizeUneven() throws {
        let (url, left, right) = try makeLanes("uneven.wav")
        try Self.left(0..<2_000).withUnsafeBufferPointer { try left.append($0) }
        try Self.right(0..<1_500).withUnsafeBufferPointer { try right.append($0) }
        try left.finalize()
        try right.finalize()  // a second finalize, from the other lane, does nothing
        #expect(try StemFile.inspect(url).frameCount == 2_000)
        let samples = try StemWriter.readSamples(url: url, frames: 1_500..<2_000)
        #expect(stride(from: 0, to: samples.count, by: 2).map { samples[$0] } == Self.left(1_500..<2_000))
        #expect(stride(from: 1, to: samples.count, by: 2).allSatisfy { samples[$0] == 0 })
    }

    @Test("Markers set through either lane are written once into the stereo Stem")
    func markers() throws {
        let (url, left, right) = try makeLanes("marked.wav")
        try Self.left(0..<1_000).withUnsafeBufferPointer { try left.append($0) }
        try Self.right(0..<1_000).withUnsafeBufferPointer { try right.append($0) }
        let markers = [StemMarker(position: 500, label: "Chorus")]
        #expect(try left.setMarkers(markers) == 1)
        #expect(try right.setMarkers(markers) == 1)
        try left.finalize()
        try right.finalize()
        let data = try Data(contentsOf: url)
        #expect(data.ranges(of: Data("Chorus".utf8)).count == 1)
    }

    @Test("Lanes on a resumed stereo Stem (a Drive that came back) carry on after its frames")
    func resumed() throws {
        let url = folder.appending(path: "resumed.wav")
        let first = StereoPair.lanes(writingTo: try StemWriter(url: url, info: Self.info))
        try Self.left(0..<1_000).withUnsafeBufferPointer { try first.left.append($0) }
        try Self.right(0..<1_000).withUnsafeBufferPointer { try first.right.append($0) }
        try first.left.commitHeader()
        try first.left.finalize()

        let again = StereoPair.lanes(writingTo: try StemWriter.open(url: url, info: Self.info, resumingAt: 1_000))
        #expect(again.left.frameCount == 1_000)
        #expect(again.right.frameCount == 1_000)
        try Self.left(1_000..<2_000).withUnsafeBufferPointer { try again.left.append($0) }
        try Self.right(1_000..<2_000).withUnsafeBufferPointer { try again.right.append($0) }
        try again.right.finalize()
        try again.left.finalize()
        #expect(try StemWriter.readSamples(url: url, frames: 0..<2_000) == StereoStemTests.frames(0..<2_000))
    }
}

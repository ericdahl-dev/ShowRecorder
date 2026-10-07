@testable import BroadcastWave
import Foundation
import Testing

/// Reading samples back out of a Stem, without going through Repair.
@Suite("Reading Stems")
struct StemReadTests {
    let folder: URL
    static let info = CrashSafeStemTests.info
    static func samples(_ range: Range<Int>) -> [Float] { CrashSafeStemTests.samples(range) }

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "StemReadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(_ name: String, frames: Int, rf64Threshold: UInt64? = nil) throws -> URL {
        let url = folder.appending(path: name)
        let writer = try rf64Threshold.map { try StemWriter(url: url, info: Self.info, rf64Threshold: $0) } ?? StemWriter(url: url, info: Self.info)
        try Self.samples(0..<frames).withUnsafeBufferPointer { try writer.append($0) }
        try writer.finalize()
        return url
    }

    @Test("A plain RIFF Stem reads back exactly what was written, whole or in any range")
    func plainRoundTrip() throws {
        let url = try write("plain.wav", frames: 5_000)
        #expect(try StemWriter.readSamples(url: url, frames: 0..<5_000) == Self.samples(0..<5_000))
        #expect(try StemWriter.readSamples(url: url, frames: 1_234..<4_321) == Self.samples(1_234..<4_321))
    }

    @Test("An RF64 Stem reads back exactly what was written")
    func rf64RoundTrip() throws {
        let url = try write("big.wav", frames: 20_000, rf64Threshold: 20_000 + UInt64(StemWriter.markerRegionSize))
        #expect(try Data(contentsOf: url).prefix(4) == Data("RF64".utf8))
        #expect(try StemWriter.readSamples(url: url, frames: 0..<20_000) == Self.samples(0..<20_000))
        #expect(try StemWriter.readSamples(url: url, frames: 19_000..<20_000) == Self.samples(19_000..<20_000))
    }

    @Test("Negative samples survive the 24-bit decode")
    func negatives() throws {
        let url = folder.appending(path: "neg.wav")
        let writer = try StemWriter(url: url, info: Self.info)
        let input: [Float] = [-1, -0.5, -1 / 8_388_608, 0, 1 / 8_388_608, 0.5]
        try input.withUnsafeBufferPointer { try writer.append($0) }
        try writer.finalize()
        #expect(try StemWriter.readSamples(url: url, frames: 0..<6) == input)
    }

    @Test("Frames past the end of the Stem read as silence")
    func pastTheEnd() throws {
        let url = try write("short.wav", frames: 100)
        #expect(try StemWriter.readSamples(url: url, frames: 90..<110) == Self.samples(90..<100) + [Float](repeating: 0, count: 10))
        #expect(try StemWriter.readSamples(url: url, frames: 200..<210) == [Float](repeating: 0, count: 10))
        #expect(try StemWriter.readSamples(url: url, frames: 5..<5).isEmpty)
    }

    @Test("A file that isn't a Stem throws")
    func notAStem() throws {
        let url = folder.appending(path: "nope.wav")
        try Data("hello".utf8).write(to: url)
        #expect(throws: (any Error).self) { try StemWriter.readSamples(url: url, frames: 0..<1) }
    }

    @Test("Reopening a Stem keeps its header and carries on after its last whole sample")
    func reopenKeepsHeader() throws {
        let url = try write("reopen.wav", frames: 1_000)
        let before = try Data(contentsOf: url).prefix(StemWriter.dataStart)

        let writer = try StemWriter.reopen(url: url)
        #expect(writer.frameCount == 1_000)
        try Self.samples(1_000..<1_500).withUnsafeBufferPointer { try writer.append($0) }
        try writer.finalize()

        let after = try Data(contentsOf: url)
        // Everything but the sizes (RIFF size, data size) is as it was: fmt, bext with the sample rate
        // and Source name, and the Marker region.
        #expect(after.prefix(StemWriter.dataStart - 4)[8...] == before.prefix(StemWriter.dataStart - 4)[8...])
        #expect(try StemWriter.readSamples(url: url, frames: 0..<1_500) == Self.samples(0..<1_500))
    }
}

import AVFoundation
@testable import BroadcastWave
import Foundation
import Testing

@Suite("RF64 Stems")
struct RF64StemTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "RF64StemTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static let info = CrashSafeStemTests.info
    static func samples(_ range: Range<Int>) -> [Float] { CrashSafeStemTests.samples(range) }
    static func read(_ url: URL) throws -> [Float] { try CrashSafeStemTests.readWithCoreAudio(url) }

    /// Header bytes before the data: RIFF(12) + JUNK/ds64(36) + fmt(24) + bext(610) + data id/size(8).
    static let headerBytes = 690

    static func bytes(_ url: URL) throws -> [UInt8] { Array(try Data(contentsOf: url)) }

    static func fourCC(_ bytes: [UInt8], at offset: Int) -> String {
        String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
    }

    static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }

    static func uint64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        (0..<8).reduce(0) { $0 | UInt64(bytes[offset + $1]) << (8 * $1) }
    }

    @Test("A Stem that stays under the limit is plain RIFF/WAVE with a JUNK chunk reserved for ds64")
    func underLimitStaysRIFF() throws {
        let url = folder.appending(path: "small.wav")
        let writer = try StemWriter(url: url, info: Self.info)
        let samples = Self.samples(0..<5_000)
        try samples.withUnsafeBufferPointer { try writer.append($0) }
        try writer.finalize()

        let bytes = try Self.bytes(url)
        #expect(Self.fourCC(bytes, at: 0) == "RIFF")
        #expect(Self.uint32(bytes, at: 4) == UInt32(bytes.count - 8))
        #expect(Self.fourCC(bytes, at: 8) == "WAVE")
        #expect(Self.fourCC(bytes, at: 12) == "JUNK")
        #expect(Self.uint32(bytes, at: 16) == 28)
        #expect(try Self.read(url) == samples)
    }

    @Test("A Stem promoted past the limit is RF64 with a ds64 chunk and reads back every sample")
    func promotedStemReadsBack() throws {
        let url = folder.appending(path: "promoted.wav")
        let threshold: UInt64 = 20_000
        let writer = try StemWriter(url: url, info: Self.info, rf64Threshold: threshold)
        let samples = Self.samples(0..<30_000)
        // Several appends, so promotion happens between buffers mid-Take.
        for start in stride(from: 0, to: samples.count, by: 1_000) {
            try samples[start..<start + 1_000].withUnsafeBufferPointer { try writer.append($0) }
        }
        try writer.finalize()

        let bytes = try Self.bytes(url)
        #expect(Self.fourCC(bytes, at: 0) == "RF64")
        #expect(Self.uint32(bytes, at: 4) == 0xFFFF_FFFF)
        #expect(Self.fourCC(bytes, at: 8) == "WAVE")
        #expect(Self.fourCC(bytes, at: 12) == "ds64")
        #expect(Self.uint32(bytes, at: 16) == 28)
        #expect(Self.uint64(bytes, at: 20) == UInt64(bytes.count - 8))
        #expect(Self.uint64(bytes, at: 28) == UInt64(samples.count * 3))
        #expect(Self.uint64(bytes, at: 36) == UInt64(samples.count))
        #expect(Self.uint32(bytes, at: 44) == 0)
        #expect(Self.fourCC(bytes, at: Self.headerBytes - 8) == "data")
        #expect(Self.uint32(bytes, at: Self.headerBytes - 4) == 0xFFFF_FFFF)
        #expect(try Self.read(url) == samples)
    }

    @Test("A promoted Stem cut off anywhere after a header commit plays back the committed audio", arguments: 0..<12)
    func promotedCutOffAfterCommitPlaysCommittedAudio(seed: Int) throws {
        let url = folder.appending(path: "promoted-cut-\(seed).wav")
        let writer = try StemWriter(url: url, info: Self.info, rf64Threshold: 20_000)
        let committed = Self.samples(0..<10_000)
        let more = Self.samples(10_000..<16_000)

        try committed.withUnsafeBufferPointer { try writer.append($0) }
        try writer.commitHeader()
        #expect(writer.isRF64)
        let committedBytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        try more.withUnsafeBufferPointer { try writer.append($0) }
        let fullBytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        var generator = SeededGenerator(seed: UInt64(seed))
        let cut = Int.random(in: committedBytes...fullBytes, using: &generator)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(cut))
        try handle.close()

        #expect(Self.fourCC(try Self.bytes(url), at: 0) == "RF64")
        #expect(try Self.read(url) == committed)
    }

    @Test("Promotion is itself a header commit: a Stem cut off right after it plays back everything before it", arguments: 0..<12)
    func cutOffAfterPromotionPlaysAudioBeforeIt(seed: Int) throws {
        let url = folder.appending(path: "promotion-cut-\(seed).wav")
        let writer = try StemWriter(url: url, info: Self.info, rf64Threshold: 20_000)
        let before = Self.samples(0..<6_000)
        let crossing = Self.samples(6_000..<8_000)

        try before.withUnsafeBufferPointer { try writer.append($0) }
        let beforeBytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        // No commitHeader: the append that crosses the limit promotes, committing `before`.
        try crossing.withUnsafeBufferPointer { try writer.append($0) }
        #expect(writer.isRF64)
        let fullBytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        var generator = SeededGenerator(seed: UInt64(seed))
        let cut = Int.random(in: beforeBytes...fullBytes, using: &generator)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(cut))
        try handle.close()

        #expect(try Self.read(url) == before)
    }

    @Test("A Stem whose pad byte would reach the limit is promoted when finalized")
    func padBytePromotesOnFinalize() throws {
        let url = folder.appending(path: "pad.wav")
        // 1,001 frames is an odd data size, ending the RIFF one byte below the threshold.
        let samples = Self.samples(0..<1_001)
        let riffSize = UInt64(Self.headerBytes - 8 + samples.count * 3)
        let writer = try StemWriter(url: url, info: Self.info, rf64Threshold: riffSize + 1)
        try samples.withUnsafeBufferPointer { try writer.append($0) }
        try writer.commitHeader()
        #expect(!writer.isRF64)
        try writer.finalize()

        let bytes = try Self.bytes(url)
        #expect(Self.fourCC(bytes, at: 0) == "RF64")
        #expect(Self.uint64(bytes, at: 20) == riffSize + 1)
        #expect(Self.uint64(bytes, at: 28) == UInt64(samples.count * 3))
        #expect(try Self.read(url) == samples)
    }

    @Test("A plain RIFF Stem's size never reaches the threshold")
    func riffSizeStaysBelowThreshold() throws {
        let url = folder.appending(path: "edge.wav")
        let samples = Self.samples(0..<1_000)
        let riffSize = UInt64(Self.headerBytes - 8 + samples.count * 3)
        let atLimit = try StemWriter(url: url, info: Self.info, rf64Threshold: riffSize)
        try samples.withUnsafeBufferPointer { try atLimit.append($0) }
        #expect(atLimit.isRF64)
        try atLimit.finalize()

        let below = try StemWriter(url: url, info: Self.info, rf64Threshold: riffSize + 1)
        try samples.withUnsafeBufferPointer { try below.append($0) }
        try below.finalize()
        #expect(!below.isRF64)
        #expect(Self.fourCC(try Self.bytes(url), at: 0) == "RIFF")
        #expect(try Self.read(url) == samples)
    }
}

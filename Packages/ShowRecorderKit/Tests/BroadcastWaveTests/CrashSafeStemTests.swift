import AVFoundation
@testable import BroadcastWave
import Foundation
import Testing

@Suite("Crash-safe Stems")
struct CrashSafeStemTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "CrashSafeStemTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static let info = StemWriter.Info(
        sampleRate: 48_000, description: "USB 01", originator: "ShowRecorder", timeReference: 0, originationDate: .now)

    /// Exactly representable in 24 bits.
    static func samples(_ range: Range<Int>) -> [Float] {
        range.map { Float($0 % 100_000) / 8_388_608 }
    }

    /// Reads a file with Core Audio, as a DAW or the Files app would.
    static func readWithCoreAudio(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0 else { return [] }
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    @Test("A Stem cut off anywhere after a header commit plays back the committed audio", arguments: 0..<12)
    func cutOffAfterCommitPlaysCommittedAudio(seed: Int) throws {
        let url = folder.appending(path: "stem-\(seed).wav")
        let writer = try StemWriter(url: url, info: Self.info)
        let committed = Self.samples(0..<10_000)
        let more = Self.samples(10_000..<16_000)

        try committed.withUnsafeBufferPointer { try writer.append($0) }
        try writer.commitHeader()
        let committedBytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        try more.withUnsafeBufferPointer { try writer.append($0) }
        // Simulate a crash: no finalize, file cut at a random point after the commit.
        let fullBytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        var generator = SeededGenerator(seed: UInt64(seed))
        let cut = Int.random(in: committedBytes...fullBytes, using: &generator)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(cut))
        try handle.close()

        #expect(try Self.readWithCoreAudio(url) == committed)
    }
}

/// SplitMix64, so the random cut points are the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Finalizing after a failed header commit")
struct FailedCommitFinalizeTests {
    @Test("Finalizing after a header commit whose flush failed keeps sample 0 and the sizes intact (#878)")
    func finalizeAfterFailedCommitKeepsAudio() throws {
        struct Dead: Error {}
        let folder = FileManager.default.temporaryDirectory.appending(path: "FailedCommitFinalizeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "d.wav")
        let writer = try StemWriter(url: url, info: CrashSafeStemTests.info)
        // An odd frame count, so finalize writes a pad byte.
        let samples = CrashSafeStemTests.samples(1..<1_002)
        try samples.withUnsafeBufferPointer { try writer.append($0) }
        writer.flush = { _ in throw Dead() }
        #expect(throws: Dead.self) { try writer.commitHeader() }

        // What the writer thread does when a write fails: close what can be closed.
        try writer.finalize()

        let data = try Data(contentsOf: url)
        func size(at offset: Int) -> Int { data[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | Int($1) } }
        #expect(try StemWriter.readSamples(url: url, frames: 0..<1_001) == samples, "sample 0 is not overwritten")
        #expect(data.count == StemWriter.dataStart + 1_001 * StemWriter.bytesPerSample + 1, "pad byte at the end, nothing else")
        #expect(size(at: StemWriter.dataStart - 4) == 1_001 * StemWriter.bytesPerSample, "data size")
        #expect(size(at: 4) == data.count - 8, "RIFF size covers the whole file")
    }
}

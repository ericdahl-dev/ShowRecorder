import AVFoundation
import BroadcastWave
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

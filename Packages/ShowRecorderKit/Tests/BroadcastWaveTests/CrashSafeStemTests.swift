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

/// What `finalize` and `commitHeader` ask of the disk (#602): a Drive pulled right after a normal Stop can lose the last
/// couple of seconds, and the header that says how long the Stem is, unless the file was flushed before it was closed.
@Suite("Flushing a Stem to disk")
struct StemFlushTests {
    final class Flushes: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func note() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "StemFlushTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @Test("Finalizing a Stem flushes it to disk after its final sizes are written and before it is closed")
    func finalizeFlushes() throws {
        let url = folder.appending(path: "a.wav")
        let writer = try StemWriter(url: url, info: CrashSafeStemTests.info)
        let flushes = Flushes()
        // What the file declared at the moment of the flush: it has to be the final sizes, or the flush protects the old ones.
        nonisolated(unsafe) var declaredAtFlush: UInt64?
        writer.flush = { _ in
            declaredAtFlush = (try? StemFile.inspect(url))?.declaredBytes
            flushes.note()
        }
        try CrashSafeStemTests.samples(0..<1_000).withUnsafeBufferPointer { try writer.append($0) }

        try writer.finalize()

        #expect(flushes.count >= 1)
        #expect(declaredAtFlush == 1_000 * UInt64(StemWriter.bytesPerSample), "flushed with its final sizes in place")
    }

    @Test("A flush that fails still closes the file, and the error reaches the caller")
    func failedFlushStillCloses() throws {
        struct Dead: Error {}
        let url = folder.appending(path: "c.wav")
        let writer = try StemWriter(url: url, info: CrashSafeStemTests.info)
        writer.flush = { _ in throw Dead() }
        try CrashSafeStemTests.samples(0..<1_000).withUnsafeBufferPointer { try writer.append($0) }

        #expect(throws: Dead.self) { try writer.finalize() }

        // Closed: with the disk answering again, a second finalize (the writer thread retries each Stem) has no open file
        // to write to, and says so. An open one would just succeed.
        writer.flush = { _ in }
        #expect(throws: (any Error).self) { try writer.finalize() }
        #expect(try StemFile.inspect(url).framesOnDisk == 1_000, "what was written is on disk")
    }

    @Test("Committing a header still flushes, once")
    func commitFlushes() throws {
        let writer = try StemWriter(url: folder.appending(path: "b.wav"), info: CrashSafeStemTests.info)
        let flushes = Flushes()
        writer.flush = { _ in flushes.note() }
        try CrashSafeStemTests.samples(0..<1_000).withUnsafeBufferPointer { try writer.append($0) }

        try writer.commitHeader()

        #expect(flushes.count == 1)
    }
}

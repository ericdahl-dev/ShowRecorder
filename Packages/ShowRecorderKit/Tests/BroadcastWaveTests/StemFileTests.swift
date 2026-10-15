@testable import BroadcastWave
import Foundation
import Testing

/// One reader for what a Stem file holds: the length its header declares and the samples actually on disk (#440).
@Suite("Stem file")
struct StemFileTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "StemFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(frames: Int, finalize: Bool = true) throws -> URL {
        let url = folder.appending(path: "\(frames).wav")
        let writer = try StemWriter(url: url, info: CrashSafeStemTests.info)
        try [Float](repeating: 0.25, count: frames).withUnsafeBufferPointer { try writer.append($0) }
        if finalize { try writer.finalize() } else { try writer.commitHeader() }
        return url
    }

    @Test("A finalized Stem's header and its samples on disk agree, odd or even", arguments: [0, 1, 4_801, 48_000])
    func finalizedLength(frames: Int) throws {
        let stem = try StemFile.inspect(write(frames: frames))
        #expect(stem.frameCount == UInt64(frames))
        #expect(stem.framesOnDisk == UInt64(frames))
        #expect(stem.dataStart == UInt64(StemWriter.dataStart))
        #expect(stem.audioRegion.offset == stem.dataStart)
        #expect(stem.audioRegion.length == UInt64(frames * StemWriter.bytesPerSample))
    }

    @Test("A Stem cut short reports only the frames it holds")
    func truncatedLength() throws {
        let url = try write(frames: 1_000, finalize: false)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size - 300))
        try handle.close()

        let stem = try StemFile.inspect(url)
        #expect(stem.frameCount == 900)
        #expect(stem.framesOnDisk == 900)
    }

    @Test("A Stem whose header lags its samples: the header's length is what a finished Stem says, the samples on disk are where writing resumes")
    func staleHeader() throws {
        let url = folder.appending(path: "stale.wav")
        let writer = try StemWriter(url: url, info: CrashSafeStemTests.info)
        try [Float](repeating: 0.25, count: 1_000).withUnsafeBufferPointer { try writer.append($0) }
        try writer.commitHeader()
        try [Float](repeating: 0.25, count: 500).withUnsafeBufferPointer { try writer.append($0) }  // a crash before the next commit

        let stem = try StemFile.inspect(url)
        #expect(stem.frameCount == 1_000)
        #expect(stem.framesOnDisk == 1_500)
        #expect(stem.declaredBytes == 3_000 && stem.bytesOnDisk == 4_500)
    }

    @Test("An RF64 Stem's length comes from ds64")
    func rf64Length() throws {
        let url = folder.appending(path: "rf64.wav")
        let writer = try StemWriter(url: url, info: CrashSafeStemTests.info, rf64Threshold: 2_000)
        try [Float](repeating: 0.25, count: 5_001).withUnsafeBufferPointer { try writer.append($0) }
        try writer.finalize()
        #expect(try Data(contentsOf: url).prefix(4) == Data("RF64".utf8))

        let stem = try StemFile.inspect(url)
        #expect(stem.frameCount == 5_001)
        #expect(stem.framesOnDisk == 5_001, "the pad byte after an odd count isn't a sample")
    }

    @Test("A file that isn't a WAV, or isn't there, throws")
    func notAWave() throws {
        let url = folder.appending(path: "x.wav")
        try Data("hello".utf8).write(to: url)
        #expect(throws: (any Error).self) { try StemFile.inspect(url) }
        #expect(throws: (any Error).self) { try StemFile.inspect(folder.appending(path: "missing.wav")) }
    }
}

@testable import BroadcastWave
import Foundation
import Testing

@Suite("Stem length")
struct StemLengthTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "StemLengthTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(frames: Int, finalize: Bool = true) throws -> URL {
        let url = folder.appending(path: "\(frames).wav")
        let writer = try StemWriter(url: url, info: CrashSafeStemTests.info)
        try [Float](repeating: 0.25, count: frames).withUnsafeBufferPointer { try writer.append($0) }
        if finalize { try writer.finalize() } else { try writer.commitHeader() }
        return url
    }

    @Test("A finalized Stem's length is its frame count, odd or even", arguments: [0, 1, 4_801, 48_000])
    func finalizedLength(frames: Int) throws {
        #expect(try StemLength.frameCount(at: write(frames: frames)) == UInt64(frames))
    }

    @Test("A Stem cut short reports only the frames it holds")
    func truncatedLength() throws {
        let url = try write(frames: 1_000, finalize: false)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size - 300))
        try handle.close()

        #expect(try StemLength.frameCount(at: url) == 900)
    }

    @Test("An RF64 Stem's length comes from ds64")
    func rf64Length() throws {
        let url = folder.appending(path: "rf64.wav")
        let writer = try StemWriter(url: url, info: CrashSafeStemTests.info, rf64Threshold: 2_000)
        try [Float](repeating: 0.25, count: 5_001).withUnsafeBufferPointer { try writer.append($0) }
        try writer.finalize()
        #expect(try Data(contentsOf: url).prefix(4) == Data("RF64".utf8))

        #expect(try StemLength.frameCount(at: url) == 5_001)
    }

    @Test("A file that isn't a WAV throws")
    func notAWave() throws {
        let url = folder.appending(path: "x.wav")
        try Data("hello".utf8).write(to: url)
        #expect(throws: (any Error).self) { try StemLength.frameCount(at: url) }
    }
}

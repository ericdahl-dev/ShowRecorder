@testable import BroadcastWave
import Foundation
import Testing

/// Repair of one Stem from a Stem that starts partway into the Take: a Drive only Take's Device stand-in
/// holds just the stretch the Drive missed (#196, ADR 0006).
@Suite("Repairing a Stem from a stand-in")
struct StemRepairTests {
    let folder: URL
    static let info = CrashSafeStemTests.info
    static func samples(_ range: Range<Int>) -> [Float] { CrashSafeStemTests.samples(range) }

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "StemRepairTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(_ name: String, _ samples: [Float]) throws -> URL {
        let url = folder.appending(path: name)
        let writer = try StemWriter(url: url, info: Self.info)
        try samples.withUnsafeBufferPointer { try writer.append($0) }
        try writer.finalize()
        return url
    }

    @Test("A Gap is filled from a stand-in whose first frame is the Gap's first Take frame")
    func fillsFromOffsetSource() throws {
        let take = Self.samples(0..<10_000)
        // The Drive Copy has silence where the Drive was lost, Take frames 3,000 to 7,000.
        let drive = try write("drive.wav", Array(take[0..<3_000]) + [Float](repeating: 0, count: 4_000) + Array(take[7_000..<10_000]))
        // The stand-in holds only those frames.
        let standIn = try write("stand-in.wav", Array(take[3_000..<7_000]))

        try StemRepair.fill(target: drive, from: standIn, sourceStart: 3_000, ranges: [3_000..<7_000], length: 10_000, markers: [])

        #expect(try StemWriter.readSamples(url: drive, frames: 0..<10_000) == take)
    }
}

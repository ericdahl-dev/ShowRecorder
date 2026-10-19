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

    @Test("Where the source ends early, the target's own frames past that are left as they are, not overwritten with silence (#602)")
    func shortSourceLeavesTheTargetAlone() throws {
        let take = Self.samples(0..<1_000)
        // The target holds real audio all the way, though its Gap says 300 to 800 (an uncommitted tail that did reach the disk).
        let target = try write("target.wav", take)
        // The source holds only the first 500 frames of the Take.
        let source = try write("source.wav", Array(take[0..<500]).map { $0 * 0.5 })

        try StemRepair.fill(target: target, from: source, ranges: [300..<800], length: 1_000, markers: [])

        let result = try StemWriter.readSamples(url: target, frames: 0..<1_000)
        #expect(Array(result[300..<500]) == (try StemWriter.readSamples(url: source, frames: 300..<500)), "what the source has is copied")
        #expect(Array(result[500..<800]) == Array(take[500..<800]), "what it lacks stays as the target had it")
        #expect(Array(result[800..<1_000]) == Array(take[800..<1_000]))
    }

    @Test("A source with nothing at all in the range changes nothing")
    func emptySourceChangesNothing() throws {
        let take = Self.samples(0..<1_000)
        let target = try write("target.wav", take)
        let source = try write("source.wav", [])

        try StemRepair.fill(target: target, from: source, ranges: [0..<1_000], length: 1_000, markers: [])

        #expect(try StemWriter.readSamples(url: target, frames: 0..<1_000) == take)
    }
}

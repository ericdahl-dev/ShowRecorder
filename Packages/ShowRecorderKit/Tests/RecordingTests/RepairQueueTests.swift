import BroadcastWave
import Destinations
import Foundation
import MixerLink
@testable import Recording
import Testing

/// The Repair queue on its own: no recorder, no recorded Takes.
@MainActor
@Suite("Repair queue")
struct RepairQueueTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "RepairQueueTests-\(UUID().uuidString)")
    }

    /// What the stand-in Repair was asked, and a way to hold it until a test lets it go.
    final class Runner: @unchecked Sendable {
        private let lock = NSLock()
        private var _skips: [Set<DestinationKind>] = []
        private var _takes: [Int] = []
        let gate = DispatchSemaphore(value: 0)
        var held = false

        var skips: [Set<DestinationKind>] { lock.withLock { _skips } }
        var takes: [Int] { lock.withLock { _takes } }

        func run(copies: [TakeRepair.Copy], metadata: TakeMetadata, skip: Set<DestinationKind>) -> [TakeMetadata.Repair] {
            lock.withLock { _skips.append(skip); _takes.append(metadata.take) }
            if held && metadata.take == 1 { gate.wait() }
            return metadata.gaps.filter { !skip.contains($0.copy) }.map { .init(copy: $0.copy, start: $0.start, end: $0.end, outcome: .repaired) }
        }
    }

    func folders(_ name: String, deviceFrames: Int = 0, driveFrames: Int = 0) throws -> [URL] {
        try [("Device", deviceFrames), ("Drive", driveFrames)].map { copy, frames in
            let folder = root.appending(path: "\(name)/\(copy)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: RecordingTakeTests.showDay)
            let stem = try StemWriter.open(url: folder.appending(path: "01 USB 01.wav"), info: info, resumingAt: nil)
            try [Float](repeating: 0.1, count: frames).withUnsafeBufferPointer { try stem.append($0) }
            try stem.finalize()
            return folder
        }
    }

    func metadata(take: Int, gaps: [TakeMetadata.Gap]) -> TakeMetadata {
        var metadata = TakeMetadata(
            show: "Show", take: take, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        metadata.gaps = gaps
        return metadata
    }

    let driveGap = TakeMetadata.Gap(copy: .drive, start: 480, end: 4800)

    @Test("A Take with no Gaps is complete at once, releases its access and runs nothing")
    func noGaps() throws {
        let runner = Runner()
        let queue = RepairQueue(freeSpace: { _ in .max }, run: runner.run)
        var released = 0
        queue.enqueue(metadata(take: 1, gaps: []), folders: try folders("a"), holding: DestinationAccess(folder: root, release: { released += 1 }))

        #expect(queue.outcomes == [.device: .complete, .drive: .complete])
        #expect(!queue.isRunning)
        #expect(released == 1)
        #expect(runner.takes.isEmpty)
    }

    @Test("A Take with Gaps shows them as unrepaired until Repair has run, then holds its access to the end")
    func repairsAndReleases() async throws {
        let runner = Runner()
        let queue = RepairQueue(freeSpace: { _ in .max }, run: runner.run)
        var released = 0
        var changes = 0
        queue.onChange = { changes += 1 }
        queue.enqueue(metadata(take: 1, gaps: [driveGap]), folders: try folders("a", deviceFrames: 4800, driveFrames: 480), holding: DestinationAccess(folder: root, release: { released += 1 }))

        #expect(queue.outcomes == [.device: .complete, .drive: .hasGaps])
        #expect(queue.isRunning)
        #expect(released == 0)

        await queue.wait()
        #expect(queue.outcomes == [.device: .complete, .drive: .repaired])
        #expect(!queue.isRunning)
        #expect(released == 1)
        #expect(changes >= 3)
    }

    @Test("Only the latest Take's Repair sets the outcome, even when an earlier Take's finishes after the later one is queued")
    func latestTakeWins() async throws {
        let runner = Runner()
        runner.held = true
        let queue = RepairQueue(freeSpace: { _ in .max }, run: runner.run)
        var seenWhenFirstDone: [DestinationKind: CopyOutcome]?
        queue.jobDone = { if seenWhenFirstDone == nil { seenWhenFirstDone = queue.outcomes } }

        queue.enqueue(metadata(take: 1, gaps: [driveGap]), folders: try folders("a", deviceFrames: 4800, driveFrames: 480), holding: nil)
        queue.enqueue(metadata(take: 2, gaps: [driveGap]), folders: try folders("b", deviceFrames: 4800, driveFrames: 480), holding: nil)
        runner.gate.signal()
        await queue.wait()

        // When Take 1's Repair finished, Take 2 had been queued: its Gaps showed, not Take 1's result.
        #expect(seenWhenFirstDone == [.device: .complete, .drive: .hasGaps])
        #expect(runner.takes == [1, 2])
        #expect(queue.outcomes == [.device: .complete, .drive: .repaired])
        #expect(!queue.isRunning)
    }

    @Test("Repair is skipped for a Copy it would fill past the space reserve")
    func reserveKept() async throws {
        let runner = Runner()
        let reserve = SpaceReserve(channelCount: 1, sampleRate: 48_000)
        let drive = root.appending(path: "a/Drive").path
        // The Drive Copy stopped at 480 frames and would grow by 4320 frames of 24-bit audio.
        let extra = Int64(4320 * StemWriter.bytesPerSample)
        let queue = RepairQueue(freeSpace: { $0.path == drive ? reserve.bytes + extra - 1 : .max }, run: runner.run)

        queue.enqueue(metadata(take: 1, gaps: [driveGap]), folders: try folders("a", deviceFrames: 4800, driveFrames: 480), holding: nil)
        await queue.wait()
        #expect(runner.skips == [[.drive]])
        #expect(queue.outcomes[.drive] == .hasGaps)

        // One byte more room and it is repaired.
        let roomy = RepairQueue(freeSpace: { $0.path == drive ? reserve.bytes + extra : .max }, run: runner.run)
        roomy.enqueue(metadata(take: 2, gaps: [driveGap]), folders: try folders("b", deviceFrames: 4800, driveFrames: 480), holding: nil)
        await roomy.wait()
        #expect(runner.skips.last == [])
    }
}

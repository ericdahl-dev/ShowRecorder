import BroadcastWave
import Destinations
import Foundation

/// Repair (#14): after a Take ends, fills each Copy's Gaps from the other Copy. Takes are repaired one at a
/// time in the order they ended, and the latest Take's Copy outcomes are published. `Recorder` publishes
/// `outcomes` and `isRunning`; it does not schedule anything.
@MainActor
final class TakeRepair {
    /// Fills the Gaps of `copies` from each other and returns what happened. `TakeRepair.fill` in the app.
    typealias Run = @Sendable (_ copies: [Copy], _ metadata: TakeMetadata, _ skip: Set<DestinationKind>) -> [TakeMetadata.Repair]

    /// How each Copy of the latest Take to be enqueued ended up. Once its Repair has run, with the result.
    private(set) var outcomes: [DestinationKind: CopyOutcome] = [:]
    /// Whether any Repair is still queued or running.
    private(set) var isRunning = false
    /// Called after `outcomes` or `isRunning` changes.
    var onChange: () -> Void = {}
    /// Called after each Repair has written its result into the Take's folders.
    var jobDone: () -> Void = {}

    private let freeSpace: (URL) -> Int64
    private let run: Run
    private var task: Task<Void, Never>?
    /// Counts enqueued Takes, so only the latest one's Repair sets `outcomes`.
    private var generation = 0
    private var pending = 0

    /// - Parameters:
    ///   - freeSpace: free bytes on a Destination, read when a Take is enqueued.
    ///   - run: does the Repair; replaced in tests.
    init(freeSpace: @escaping (URL) -> Int64, run: @escaping Run = { TakeRepair.fill(copies: $0, metadata: $1, skip: $2) }) {
        self.freeSpace = freeSpace
        self.run = run
    }

    /// Queues Repair of an ended Take: fills its Gaps from the other Copy, off the main thread, and
    /// records the result in `Take.json`. `access` (the Drive's folder) is held until it's done.
    /// A Take with no Gaps has nothing to repair; its outcomes are complete and `access` is released.
    func enqueue(_ metadata: TakeMetadata, folders: [URL], holding access: DriveAccess?) {
        func outcomes(_ metadata: TakeMetadata) -> [DestinationKind: CopyOutcome] {
            Dictionary(uniqueKeysWithValues: folders.indices.map { (DestinationKind(index: $0), metadata.outcome(ofCopy: DestinationKind(index: $0))) })
        }
        generation += 1
        let mine = generation
        self.outcomes = outcomes(metadata)
        onChange()
        guard !metadata.gaps.isEmpty else {
            access?.end()
            return
        }
        let copies = folders.indices.map { Copy(kind: DestinationKind(index: $0), folder: folders[$0]) }
        // Repair must not fill a Destination past the space reserve: a Copy stopped for being nearly
        // full stays as it is, with its Gaps.
        let reserve = SpaceReserve(channelCount: metadata.usbChannels.count, sampleRate: metadata.sampleRate)
        let skip = Set(copies.filter { copy in
            reserve.wouldBreach(free: freeSpace(copy.folder), adding: Self.bytesToExtend(copy, in: copies, metadata: metadata))
        }.map(\.kind))
        pending += 1
        isRunning = true
        onChange()
        let previous = task
        let run = run
        task = Task { [weak self] in
            await previous?.value
            let repairs = await Task.detached { run(copies, metadata, skip) }.value
            var done = metadata
            done.repairs = repairs
            for folder in folders { try? done.write(to: folder) }
            guard let self else {
                access?.end()
                return
            }
            if mine == generation { self.outcomes = outcomes(done) }
            jobDone()
            access?.end()
            pending -= 1
            isRunning = pending > 0
            onChange()
        }
    }

    /// Waits for the latest enqueued Repair to finish (earlier ones finish first).
    func wait() async {
        await task?.value
    }

    // MARK: - Filling Gaps

    struct Copy: Sendable {
        var kind: DestinationKind
        var folder: URL
    }

    /// The Take's length in frames: the longest Stem in any Copy, or the end of the last Gap.
    nonisolated private static func length(copies: [Copy], metadata: TakeMetadata) -> Int {
        let stems = metadata.usbChannels.map(\.stemFile)
        return max(
            metadata.gaps.map(\.end).max() ?? 0,
            copies.flatMap { copy in stems.map { Int(StemWriter.frameCount(of: copy.folder.appending(path: $0)) ?? 0) } }.max() ?? 0)
    }

    /// Bytes Repair would add to `copy`'s Stems to bring them to the Take's length. Filling a Gap in the
    /// middle needs no space; only a Copy that stopped early grows.
    nonisolated private static func bytesToExtend(_ copy: Copy, in copies: [Copy], metadata: TakeMetadata) -> Int64 {
        let length = length(copies: copies, metadata: metadata)
        return metadata.usbChannels.reduce(into: Int64(0)) { total, channel in
            let frames = Int(StemWriter.frameCount(of: copy.folder.appending(path: channel.stemFile)) ?? 0)
            total += Int64(max(length - frames, 0) * StemWriter.bytesPerSample)
        }
    }

    /// Repairs every Copy that has Gaps from the other Copy and returns what happened to each Gap.
    /// A Gap is repaired only if the other Copy has the samples; where both Copies are missing the
    /// same stretch it stays silence and is reported as failed. Copies named in `skip` are left alone
    /// and get no entry: they stay as they were, with their Gaps.
    nonisolated static func fill(copies: [Copy], metadata: TakeMetadata, skip: Set<DestinationKind> = []) -> [TakeMetadata.Repair] {
        let markers = metadata.markers.map { StemMarker(position: UInt32(clamping: $0.position), label: $0.name) }
        let stems = metadata.usbChannels.map(\.stemFile)
        let length = length(copies: copies, metadata: metadata)

        var repairs: [TakeMetadata.Repair] = []
        for target in copies where !skip.contains(target.kind) {
            let gaps = metadata.gaps.filter { $0.copy == target.kind }
            guard !gaps.isEmpty else { continue }
            let source = copies.first { $0.kind != target.kind }
            let sourceGaps = metadata.gaps.filter { $0.copy != target.kind }.map { $0.start..<$0.end }

            var copied = source != nil
            if let source {
                do {
                    for stem in stems {
                        try StemRepair.fill(
                            target: target.folder.appending(path: stem), from: source.folder.appending(path: stem),
                            ranges: gaps.map { $0.start..<$0.end }, length: length, markers: markers)
                    }
                } catch {
                    copied = false
                }
            }
            for gap in gaps {
                let range = gap.start..<gap.end
                let sourceHasIt = !sourceGaps.contains { $0.overlaps(range) }
                repairs.append(.init(copy: gap.copy, start: gap.start, end: gap.end, outcome: copied && sourceHasIt ? .repaired : .failed))
            }
        }
        return repairs
    }
}

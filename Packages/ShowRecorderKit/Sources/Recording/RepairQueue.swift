import Destinations
import Foundation

/// Runs Repair for ended Takes, one at a time in the order they ended, and says how the latest Take's
/// Copies turned out. `Recorder` publishes `outcomes` and `isRunning`; it does not schedule anything.
@MainActor
final class RepairQueue {
    /// Fills the Gaps of `copies` from each other and returns what happened. `TakeRepair.run` in the app.
    typealias Run = @Sendable (_ copies: [TakeRepair.Copy], _ metadata: TakeMetadata, _ skip: Set<DestinationKind>) -> [TakeMetadata.Repair]

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
    init(freeSpace: @escaping (URL) -> Int64, run: @escaping Run = { TakeRepair.run(copies: $0, metadata: $1, skip: $2) }) {
        self.freeSpace = freeSpace
        self.run = run
    }

    /// Queues Repair of an ended Take: fills its Gaps from the other Copy, off the main thread, and
    /// records the result in `Take.json`. `access` (the Drive's folder) is held until it's done.
    /// A Take with no Gaps has nothing to repair; its outcomes are complete and `access` is released.
    func enqueue(_ metadata: TakeMetadata, folders: [URL], holding access: DestinationAccess?) {
        func outcomes(_ metadata: TakeMetadata) -> [DestinationKind: CopyOutcome] {
            Dictionary(uniqueKeysWithValues: folders.indices.map { (DestinationKind(index: $0), metadata.outcome(ofCopy: DestinationKind(index: $0))) })
        }
        generation += 1
        let mine = generation
        self.outcomes = outcomes(metadata)
        onChange()
        guard !metadata.gaps.isEmpty else {
            access?.release()
            return
        }
        let copies = folders.indices.map { TakeRepair.Copy(kind: DestinationKind(index: $0), folder: folders[$0]) }
        // Repair must not fill a Destination past the space reserve: a Copy stopped for being nearly
        // full stays as it is, with its Gaps.
        let reserve = SpaceReserve(channelCount: metadata.usbChannels.count, sampleRate: metadata.sampleRate)
        let skip = Set(copies.filter { copy in
            reserve.wouldBreach(free: freeSpace(copy.folder), adding: TakeRepair.bytesToExtend(copy, in: copies, metadata: metadata))
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
                access?.release()
                return
            }
            if mine == generation { self.outcomes = outcomes(done) }
            jobDone()
            access?.release()
            pending -= 1
            isRunning = pending > 0
            onChange()
        }
    }

    /// Waits for the latest enqueued Repair to finish (earlier ones finish first).
    func wait() async {
        await task?.value
    }
}

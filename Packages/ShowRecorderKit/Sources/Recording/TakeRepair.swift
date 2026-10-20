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
    /// Drive only: whether Repair moved the latest Take's stand-in to the Drive and off the Device.
    private(set) var moved = false
    /// Drive only: whether the latest Take's stand-in is still on the Device after its Repair.
    private(set) var standInKept = false
    /// Whether any Repair is still queued or running.
    private(set) var isRunning = false
    /// Called after `outcomes` or `isRunning` changes.
    var onChange: () -> Void = {}
    /// Called after each Repair has written its result into the Take's folders, with the Copies Stop gave up on in it.
    var jobDone: (_ abandoned: Set<DestinationKind>) -> Void = { _ in }

    private let freeSpace: (URL) -> Int64
    private let run: Run
    private let writeAbandoned: @Sendable (TakeMetadata, URL) -> Void
    private var task: Task<Void, Never>?
    /// Counts enqueued Takes, so only the latest one's Repair sets `outcomes`.
    private var generation = 0
    private var pending = 0

    /// - Parameters:
    ///   - freeSpace: free bytes on a Destination, read when a Take is enqueued.
    ///   - run: does the Repair; replaced in tests.
    ///   - writeAbandoned: writes `Take.json` to a Copy Stop gave up on, off the main thread; replaced in tests.
    init(
        freeSpace: @escaping (URL) -> Int64, run: @escaping Run = { TakeRepair.fill(copies: $0, metadata: $1, skip: $2) },
        writeAbandoned: @escaping @Sendable (TakeMetadata, URL) -> Void = { try? $0.write(to: $1) }
    ) {
        self.freeSpace = freeSpace
        self.run = run
        self.writeAbandoned = writeAbandoned
    }

    /// Queues Repair of an ended Take: fills its Gaps from the other Copy, off the main thread, and
    /// records the result in `Take.json`. `access` (the Drive's folder) is held until it's done.
    /// A Take with no Gaps has nothing to repair; its outcomes are complete (but a spare Drive only stand-in is removed,
    /// so the Device has none) and `access` is released, once the `Take.json` of any Copy Stop gave up on is written.
    /// - Parameters:
    ///   - abandoned: Copies Stop gave up on (#320), left as they are.
    ///   - keepsStandIns: a Drive only stand-in stays on the Device even once the Drive has its audio: a Take cut off
    ///     by a crash may not know all its Gaps, so its stand-in may hold the only copy of some audio (#626).
    func enqueue(
        _ metadata: TakeMetadata, folders: [DestinationKind: URL], holding access: DriveAccess?, abandoned: Set<DestinationKind> = [],
        keepsStandIns: Bool = false, publishing: Bool = true
    ) {
        func outcomes(_ metadata: TakeMetadata) -> [DestinationKind: CopyOutcome] {
            Dictionary(uniqueKeysWithValues: folders.keys.map { ($0, metadata.outcome(ofCopy: $0)) })
        }
        // A Take that isn't the latest (a recovered earlier one, #822) repairs without taking the latest's place in `outcomes`.
        if publishing { generation += 1 }
        let mine = publishing ? generation : -1
        if publishing {
            self.outcomes = outcomes(metadata)
            moved = false
            standInKept = false
            onChange()
        }
        // A Copy Stop gave up on (#320) may hang on any file operation, so its Take.json is written off the main thread, as a
        // step of this queue: Repair's own write, and renames that wait for Repair, come after it (#652). If that Drive hangs for
        // good, the queue waits on it: later Repairs, renames, Drive only moves and anything awaiting Repair (Soundcheck's
        // `waitForRepair`) stall behind it, as Repair of its Gaps already did. Accepted until option A.
        let abandonedFolders = abandoned.compactMap { folders[$0] }
        if !abandonedFolders.isEmpty {
            let previous = task, write = writeAbandoned
            // Repair is running while that write is pending, so `isRepairing` says so and waiters know (#673).
            pending += 1
            isRunning = true
            onChange()
            task = Task { [weak self] in
                await previous?.value
                await runOffPool { for folder in abandonedFolders { write(metadata, folder) } }
                guard let self else { return }
                pending -= 1
                isRunning = pending > 0
                onChange()
            }
        }
        guard !metadata.gaps.isEmpty else {
            // Drive only: a Drive that faltered but then caught up has the whole Take, so its stand-in is a spare. Not one on
            // a Device Stop gave up on: its writer may still be going and that volume may be what hangs, so nothing is
            // removed there, and never on the main thread (#664).
            if publishing, !keepsStandIns, metadata.standIns != nil, let device = folders[.device], let drive = folders[.drive],
               !abandoned.contains(.drive), !abandoned.contains(.device) {
                var done = metadata
                done.standIns = nil
                // The stand-ins go only once the Drive's Take.json no longer names them (#879).
                if (try? done.write(to: drive)) != nil { try? FileManager.default.removeItem(at: device) }
                // So the Take has no Device Copy (#621).
                self.outcomes[.device] = nil
                onChange()
            } else if !keepsStandIns, metadata.standIns != nil, abandoned.contains(.device), !abandoned.contains(.drive) {
                // The stand-in stays on a Device Stop gave up on: the summary says so, as after a Repair that kept it.
                standInKept = true
                onChange()
            }
            if abandonedFolders.isEmpty {
                access?.end()
            } else {
                // Held until the abandoned Copies' Take.json is written.
                let previous = task
                task = Task { await previous?.value; access?.end() }
            }
            return
        }
        let copies = DestinationKind.allCases.compactMap { kind in folders[kind].map { Copy(kind: kind, folder: $0) } }
        // Repair must not fill a Destination past the space reserve: a Copy stopped for being nearly
        // full stays as it is, with its Gaps. A Copy Stop gave up on isn't read here, on the main thread (#652).
        let reserve = SpaceReserve(channelCount: metadata.usbChannels.count, sampleRate: metadata.sampleRate)
        let healthy = copies.filter { !abandoned.contains($0.kind) }
        let skip = Set(healthy.filter { copy in
            reserve.wouldBreach(free: freeSpace(copy.folder), adding: Self.bytesToExtend(copy, in: healthy, metadata: metadata))
        }.map(\.kind)).union(abandoned)
        pending += 1
        isRunning = true
        onChange()
        let previous = task
        let run = run, write = writeAbandoned
        task = Task { [weak self] in
            await previous?.value
            let repairs = await runOffPool { run(copies, metadata, skip) }
            var done = metadata
            done.repairs = repairs
            // Drive only: once the Drive Copy has everything, nothing of the Take stays on the Device.
            // Not off a Device Stop gave up on: its folder isn't removed, so the stand-ins stay named (#664).
            let moved = !keepsStandIns && metadata.standIns != nil && done.outcome(ofCopy: .drive) == .repaired
                && !abandoned.contains(.device)
            // The stand-ins' folders are gone once moved, so the Take no longer names them.
            if moved { done.standIns = nil }
            // Every write to a Destination (a Drive that may have gone away) is off the cooperative pool.
            await runOffPool { [done] in
                // The Device's folder goes only when the Drive has the moved audio; a lone Copy is never removed.
                let removesDevice = moved && copies.contains { $0.kind == .drive }
                var driveWritten = false
                for copy in copies where !(removesDevice && copy.kind == .device) {
                    if abandoned.contains(copy.kind) {
                        write(done, copy.folder)
                    } else {
                        let written = (try? done.write(to: copy.folder)) != nil
                        if copy.kind == .drive { driveWritten = written }
                    }
                }
                // Only once the Drive's Take.json no longer names the stand-ins, so a failed write never strands it (#879).
                if removesDevice, driveWritten, let device = copies.first(where: { $0.kind == .device }) {
                    try? FileManager.default.removeItem(at: device.folder)
                }
            }
            guard let self else {
                access?.end()
                return
            }
            if publishing, mine == generation {
                self.outcomes = outcomes(done)
                self.moved = moved
                standInKept = done.standIns != nil
            }
            jobDone(abandoned)
            access?.end()
            pending -= 1
            isRunning = pending > 0
            onChange()
        }
    }

    /// Drive only (#630): queues moving `takes` (kept stand-ins, and Takes the Device holds whole) to the Drive at `access`, one
    /// Take at a time after any Repair queued before. Leaves `outcomes`, `moved` and `standInKept` alone: they are the
    /// latest Take's. `access` is held until the job ends; a `.stopped` Take ends it.
    func move(
        _ takes: [TakeMover.Movable], holding access: DriveAccess, shouldStop: @escaping @Sendable () -> Bool,
        done: @escaping (TakeMover.Movable, StandInMove.Outcome) -> Void
    ) {
        let previous = task
        task = Task {
            defer { access.end() }
            await previous?.value
            for movable in takes {
                let driveTake = access.folder.appending(path: movable.show).appending(path: movable.deviceFolder.lastPathComponent)
                let deviceTake = movable.deviceFolder
                let standIn = movable.kind == .standIn
                let outcome = await runOffPool {
                    standIn
                        ? StandInMove.run(deviceTake: deviceTake, driveTake: driveTake, shouldStop: shouldStop)
                        : DeviceTakeMove.run(deviceTake: deviceTake, driveTake: driveTake, shouldStop: shouldStop)
                }
                done(movable, outcome)
                if outcome == .stopped { break }
            }
        }
    }

    /// Drive only (#630): finishes or undoes the moves a crash cut off (`MoveRecovery`), after any Repair or move queued
    /// before. The caller holds the Drive's access until it returns. Leaves `outcomes`, `moved` and `standInKept` alone.
    func recover(deviceFolder: URL, driveFolder: URL, shouldStop: @escaping @Sendable () -> Bool) async -> [StandInMove.Result] {
        let previous = task
        let job = Task {
            await previous?.value
            return await runOffPool { MoveRecovery.run(deviceFolder: deviceFolder, driveFolder: driveFolder, shouldStop: shouldStop) }
        }
        task = Task { _ = await job.value }
        return await job.value
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
            copies.flatMap { copy in stems.map { framesOnDisk(copy.folder.appending(path: $0)) } }.max() ?? 0)
    }

    /// Every whole sample in a Stem, whatever its header says (Repair works on Stems that may not be finalized), or 0.
    nonisolated private static func framesOnDisk(_ url: URL) -> Int {
        Int((try? StemFile.inspect(url))?.framesOnDisk ?? 0)
    }

    /// Bytes Repair would add to `copy`'s Stems to bring them to the Take's length. Filling a Gap in the
    /// middle needs no space; only a Copy that stopped early grows.
    nonisolated private static func bytesToExtend(_ copy: Copy, in copies: [Copy], metadata: TakeMetadata) -> Int64 {
        let length = length(copies: copies, metadata: metadata)
        return metadata.usbChannels.reduce(into: Int64(0)) { total, channel in
            let frames = framesOnDisk(copy.folder.appending(path: channel.stemFile))
            total += Int64(max(length - frames, 0) * StemWriter.bytesPerSample)
        }
    }

    /// The frames every Stem in `folder` holds (a Copy is as long as its shortest Stem); 0 when one can't be read.
    nonisolated static func framesHeld(in folder: URL, stems: [String]) -> Int {
        var shortest = Int.max
        for stem in stems {
            guard let file = try? StemFile.inspect(folder.appending(path: stem)) else { return 0 }
            shortest = min(shortest, Int(file.framesOnDisk))
        }
        return shortest == .max ? 0 : shortest
    }

    /// Whether every frame of `range` is in one of `parts`, which may overlap or come in any order.
    nonisolated static func covers(_ parts: [Range<Int>], _ range: Range<Int>) -> Bool {
        var next = range.lowerBound
        for part in parts.map({ $0.clamped(to: range) }).filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard part.lowerBound <= next else { return false }
            next = max(next, part.upperBound)
        }
        return next >= range.upperBound
    }

    /// Repairs every Copy that has Gaps from the other Copy and returns what happened to each Gap.
    /// A Gap is repaired only if the other Copy has the samples; where both Copies are missing the
    /// same stretch it stays silence and is reported as failed. Copies named in `skip` are left alone
    /// and get no entry: they stay as they were, with their Gaps.
    /// - Parameter shouldStop: asked between pieces of each Stem; a stopped Stem's Gaps are reported failed, so a caller
    ///   that stopped it leaves them unrecorded for a later Repair (#630).
    nonisolated static func fill(
        copies: [Copy], metadata: TakeMetadata, skip: Set<DestinationKind> = [], shouldStop: () -> Bool = { false }
    ) -> [TakeMetadata.Repair] {
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
            // Drive only: the Device holds stand-ins, each starting at its own Take frame, instead of a Copy.
            let standIns = target.kind == .drive ? metadata.standIns : nil
            if let source {
                do {
                    for stem in stems {
                        if let standIns {
                            for standIn in standIns {
                                let ranges = gaps.map { $0.start..<$0.end }.map { $0.clamped(to: standIn.start..<standIn.end) }.filter { !$0.isEmpty }
                                try StemRepair.fill(
                                    target: target.folder.appending(path: stem),
                                    from: source.folder.appending(path: standIn.folderName).appending(path: stem),
                                    sourceStart: standIn.start, ranges: ranges, length: length, markers: markers, shouldStop: shouldStop)
                            }
                        } else {
                            // Only frames the source holds: inside its own Gaps the target may hold frames it lacks (#630).
                            let ranges = gaps.flatMap { CopyCoverage.subtracting(sourceGaps, from: $0.start..<$0.end) }
                            try StemRepair.fill(
                                target: target.folder.appending(path: stem), from: source.folder.appending(path: stem),
                                ranges: ranges, length: length, markers: markers, shouldStop: shouldStop)
                        }
                    }
                } catch {
                    copied = false
                }
            }
            // What the source's files really hold, not only what its metadata says (#602): a Copy that stopped early, or a
            // stand-in cut short, has less than its Gaps and Stand-ins list.
            let sourceExtents: [Range<Int>]? = source.map { source in
                if let standIns {
                    return standIns.map { standIn in
                        let frames = Self.framesHeld(in: source.folder.appending(path: standIn.folderName), stems: stems)
                        return standIn.start..<min(standIn.end, standIn.start + frames)
                    }
                }
                return [0..<Self.framesHeld(in: source.folder, stems: stems)]
            }
            for gap in gaps {
                let range = gap.start..<gap.end
                let sourceHasIt = (sourceExtents.map { Self.covers($0, range) } ?? false)
                    && (standIns != nil || !sourceGaps.contains { $0.overlaps(range) })
                repairs.append(.init(copy: gap.copy, start: gap.start, end: gap.end, outcome: copied && sourceHasIt ? .repaired : .failed))
            }
        }
        return repairs
    }
}

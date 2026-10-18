import BroadcastWave
import Foundation
import Synchronization

/// Drains the ring into one Stem per USB Channel on a dedicated thread, until stopped.
final class TakeWriter: @unchecked Sendable {
    private let feed: CopyFeed
    private let ring: SampleRing
    private let stems: [any StemSink]
    private let running = Atomic<Bool>(true)
    private let finished = DispatchSemaphore(value: 0)
    private let failed = Atomic<Bool>(false)
    private let done = Atomic<Bool>(false)
    /// Set when Stop gave up waiting on this Copy (#320): from then on the writer touches its Stems no more.
    private let abandoned = Atomic<Bool>(false)
    private struct Abandoned: Error {}
    private let retired = Atomic<Bool>(false)
    /// Writes and header commits done so far: how Stop tells a Destination that is slow from one that has stopped (#817).
    private let progress = Atomic<Int>(0)
    /// Whether the real-time side ever told this Copy which Take frame it starts at.
    private let joined = Atomic<Bool>(false)
    /// Called on the writer thread when this Copy fails, so capture can stop feeding it.
    private let onFailure: @Sendable () -> Void
    private var thread: Thread?
    /// Frames between header commits, so a crash loses at most this much (#6).
    private let commitInterval: Int
    private var framesSinceCommit = 0
    /// Samples in each Stem as of its last header commit, set by the writer thread (#595).
    private let committedCounts: Mutex<[UInt64]>
    /// The stretch written as silence because this Copy joined late, as Take frames.
    private let leadGapRange = Mutex<Range<Int>?>(nil)
    /// Stretches written as silence because the ring dropped that audio, as Take frames.
    private let dropoutRanges = Mutex<[Range<Int>]>([])
    /// The operator's Markers, last set by `setMarkers`. Only the writer thread uses it.
    private var operatorMarkers: [StemMarker] = []
    /// Markers waiting to be written into the Stems by the writer thread.
    private let pendingMarkers: Mutex<[StemMarker]?>
    /// Where the Copy's first frames come from, when it starts with Pre-roll: asked once, after the
    /// real-time thread has said which Take frame the live audio starts at. Returns one array of samples
    /// per channel, as long as the frames before that point, or nil if they are no longer there.
    private let head: (() -> [[Float]]?)?
    /// What the writer thread does between looks while it waits for its join frame.
    private let joinPause: () -> Void

    init(
        feed: CopyFeed, stems: [any StemSink], commitInterval: Int, onFailure: @escaping @Sendable () -> Void = {},
        head: (() -> [[Float]]?)? = nil, markers: [StemMarker] = [],
        joinPause: @escaping () -> Void = { Thread.sleep(forTimeInterval: 0.002) }
    ) {
        self.head = head
        // Markers given here are waiting before the writer starts, so they are in the Stems before its first audio.
        pendingMarkers = Mutex(markers.isEmpty ? nil : markers)
        self.joinPause = joinPause
        self.onFailure = onFailure
        self.feed = feed
        ring = feed.ring
        self.stems = stems
        committedCounts = Mutex(stems.map(\.frameCount))
        self.commitInterval = commitInterval
    }

    /// Replaces the operator's Markers in the Stems (the writer adds Dropout Markers itself). Applied on the
    /// writer thread before its next write, and on disk from the next header commit.
    func setMarkers(_ markers: [StemMarker]) {
        pendingMarkers.withLock { $0 = markers }
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "ShowRecorder Take writer"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    /// The stretch written as silence before this Copy's first audio, because it joined after the Take began
    /// (after any Pre-roll head). Nil when it joined where its Stems already were.
    var leadGap: Range<Int>? { leadGapRange.withLock { $0 } }

    /// Frames every Stem has: the Copy's length so far. Read once the writer has stopped.
    var framesWritten: Int { Int(stems.map(\.frameCount).min() ?? 0) }

    /// Samples in each Stem, in channel order. Read once the writer has stopped.
    var stemFrameCounts: [UInt64] { stems.map(\.frameCount) }

    /// Samples in each Stem that are sure to be there: for a Copy whose write failed, only what the last header
    /// commit made durable, since the rest may have gone with the Destination (#595); likewise for one Stop gave up on,
    /// whose thread may still be writing, so its live counts can't be read (#664); otherwise all of them.
    var stemFramesKept: [UInt64] {
        failed.load(ordering: .acquiring) || wasAbandoned ? committedCounts.withLock { $0 } : stemFrameCounts
    }

    /// Frames every Stem is sure to have, as `stemFramesKept` counts them.
    var framesKept: Int { Int(stemFramesKept.min() ?? 0) }

    /// Stretches written as silence because the ring had no room for that audio.
    var dropouts: [Range<Int>] { dropoutRanges.withLock { $0 } }

    /// Writes and header commits done so far; it moves while the Destination is working, however slowly.
    var progressCount: Int { progress.load(ordering: .relaxed) }

    private func noteProgress() { _ = progress.wrappingAdd(1, ordering: .relaxed) }

    /// Whether the writer thread has finished, so its files are closed and can be reopened.
    var isFinished: Bool { done.load(ordering: .acquiring) }

    /// Whether the Take stopped before this Copy joined: it waited for a join frame that never came, so
    /// it has no audio past where it began. Read once the writer has finished.
    var neverJoined: Bool { isFinished && !joined.load(ordering: .acquiring) }

    /// Whether a write failed. The Copy stops there; the Take carries on in the other Copies.
    var hasFailed: Bool { failed.load(ordering: .acquiring) || retired.load(ordering: .acquiring) }

    /// Ends this Copy early and cleanly, for a Destination that is about to fill. What was captured is
    /// written and the Stems are finalized; the rest of the Take is a Gap in this Copy. The caller stops
    /// feeding the ring first.
    func retire() {
        retired.store(true, ordering: .releasing)
        stop()
    }

    /// Drains whatever is left, finalizes every Stem and waits for the thread to finish.
    /// A failed Copy doesn't throw: it's reported through `hasFailed`.
    func stop(timeout: Duration? = nil) {
        requestStop()
        waitStopped(until: timeout.map(Self.deadline))
    }

    /// Tells the writer to drain and finish, without waiting. Stop tells every Copy first, then waits on them all
    /// against one deadline (#652).
    func requestStop() {
        running.store(false, ordering: .releasing)
    }

    /// The deadline `timeout` from now.
    static func deadline(_ timeout: Duration) -> DispatchTime {
        .now() + Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
    }

    /// Waits for the writer to finish, until `deadline` if there is one. Call `requestStop()` first.
    func waitStopped(until deadline: DispatchTime?) {
        assert(!running.load(ordering: .relaxed), "waitStopped called before requestStop")
        if done.load(ordering: .acquiring) { return }  // already stopped
        guard let deadline else {
            finished.wait()
            return
        }
        if finished.wait(timeout: deadline) == .timedOut { abandon() }
    }

    /// A Destination that hangs (a Drive pulled mid-write) doesn't hold up Stop (#320): the Copy is abandoned and
    /// failed. A write already under way can't be taken back, but the writer starts no new one when it wakes.
    private func abandon() {
        // One that just finished is not abandoned: its Take.json would be skipped.
        guard !done.load(ordering: .acquiring) else { return }
        abandoned.store(true, ordering: .releasing)
        failed.store(true, ordering: .releasing)
    }

    /// Waits for every writer to finish. One that makes no progress for `window` is abandoned, as a hung Destination is
    /// (#320); one that is slow but still writing is waited for, however long its backlog takes (#817). Call
    /// `requestStop()` on each first. Blocks, so never on the main actor.
    static func waitAll(_ writers: [TakeWriter], noProgressFor window: Duration) {
        let clock = ContinuousClock()
        var open = Array(writers.indices)
        var counts = writers.map(\.progressCount)
        var since = writers.map { _ in clock.now }
        while !open.isEmpty {
            let now = clock.now
            open.removeAll { index in
                let writer = writers[index]
                if writer.isFinished { return true }
                let count = writer.progressCount
                if count != counts[index] {
                    counts[index] = count
                    since[index] = now
                } else if now - since[index] >= window {
                    writer.abandon()
                    return true
                }
                return false
            }
            if !open.isEmpty { Thread.sleep(forTimeInterval: 0.02) }
        }
    }

    /// Whether Stop gave up waiting on this Copy.
    var wasAbandoned: Bool { abandoned.load(ordering: .acquiring) }

    private func checkAbandoned() throws {
        if abandoned.load(ordering: .acquiring) { throw Abandoned() }
    }

    private func run() {
        do {
            // Commit once up front so even a Take that dies early leaves files that open.
            try commitHeaders()
            let join = feed.waitForJoin(while: { running.load(ordering: .acquiring) }, pause: joinPause)
            if let join {
                joined.store(true, ordering: .releasing)
                try writeLeadIn(join: join)
            }
            let didJoin = join != nil
            while didJoin {
                let stillRunning = running.load(ordering: .acquiring)
                if let markers = pendingMarkers.withLock({ pending in defer { pending = nil }; return pending }) {
                    operatorMarkers = markers
                    try writeMarkers()
                }
                let dropoutsBefore = dropoutRanges.withLock { $0.count }
                let drained = try drainOnce()
                try checkAbandoned()
                if dropoutRanges.withLock({ $0.count }) != dropoutsBefore { try writeMarkers() }
                framesSinceCommit += drained
                if framesSinceCommit >= commitInterval {
                    try commitHeaders()
                    framesSinceCommit = 0
                }
                if drained == 0 {
                    if !stillRunning { break }
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
            try checkAbandoned()
            // Audio dropped while the ring's log was full has no position: its silence goes at the end.
            let unlogged = ring.takeUnloggedDroppedFrames()
            if didJoin, unlogged > 0 {
                try writeDropout(unlogged)
                try writeMarkers()
            }
            // One slow finalize is counted like a write; a single one slower than Stop's window still looks hung.
            for stem in stems { try stem.finalize(); noteProgress() }
        } catch where !abandoned.load(ordering: .acquiring) {
            failed.store(true, ordering: .releasing)
            onFailure()
            ring.discardAll()
            // Close what can be closed, so the Stems that did get written open.
            for stem in stems { try? stem.finalize() }
        } catch {
            // Abandoned at Stop: leave the files exactly as they are.
        }
        done.store(true, ordering: .releasing)
        finished.signal()
    }

    /// Commits every Stem's header, noting how much of each is now on disk.
    private func commitHeaders() throws {
        for (index, stem) in stems.enumerated() {
            try checkAbandoned()
            try stem.commitHeader()
            noteProgress()
            let count = stem.frameCount
            committedCounts.withLock { $0[index] = count }
        }
    }

    /// Once the real-time thread has said which Take frame this Copy starts at, writes what comes before it:
    /// the Pre-roll head when there is one, then silence up to the join.
    private func writeLeadIn(join: Int) throws {
        if let head, join > 0, framesWritten == 0, let samples = head(), samples.count == stems.count,
           samples.allSatisfy({ $0.count == join }) {
            for (index, stem) in stems.enumerated() {
                try samples[index].withUnsafeBufferPointer { try stem.append($0) }
                noteProgress()
            }
        }
        let start = framesWritten
        if join > start { leadGapRange.withLock { $0 = start..<join } }
        let silence = [Float](repeating: 0, count: 4096)
        for stem in stems {
            var remaining = join - Int(stem.frameCount)
            while remaining > 0 {
                let count = min(remaining, silence.count)
                try silence.withUnsafeBufferPointer { try stem.append(UnsafeBufferPointer(rebasing: $0[..<count])) }
                noteProgress()
                remaining -= count
            }
        }
    }

    /// Writes what the ring holds. Where the ring had to drop audio, writes silence of the lost length
    /// instead, at that place in the stream, so every Stem stays as long as the Take.
    private func drainOnce() throws -> Int {
        var limit = 4096
        if let drop = ring.nextDrop(final: !running.load(ordering: .acquiring)) {
            let before = drop.storedFrames - ring.consumedFrames
            if before <= 0 {
                try writeDropout(drop.length)
                ring.consumeDrop()
                return drop.length
            }
            limit = min(limit, before)  // read up to the drop, not past it
        }
        return try ring.consume(maxFrames: limit) { channel, samples in
            try checkAbandoned()
            try stems[channel].append(samples)
            noteProgress()
        }
    }

    /// Puts the operator's Markers and a "Dropout" Marker at each stretch this Copy lost into every Stem.
    private func writeMarkers() throws {
        let dropoutMarkers = dropouts.map { StemMarker(position: UInt32(clamping: $0.lowerBound), label: "Dropout") }
        let all = (operatorMarkers + dropoutMarkers).sorted { $0.position < $1.position }
        for stem in stems { try stem.setMarkers(all); noteProgress() }
    }

    /// Writes silence for audio the ring dropped, and remembers where.
    private func writeDropout(_ frames: Int) throws {
        let start = framesWritten
        try writeSilence(frames)
        dropoutRanges.withLock { $0.append(start..<start + frames) }
    }

    private func writeSilence(_ frames: Int) throws {
        let silence = [Float](repeating: 0, count: 4096)
        for stem in stems {
            var remaining = frames
            while remaining > 0 {
                let count = min(remaining, silence.count)
                try silence.withUnsafeBufferPointer { try stem.append(UnsafeBufferPointer(rebasing: $0[..<count])) }
                noteProgress()
                remaining -= count
            }
        }
    }
}

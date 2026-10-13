import Synchronization

/// A lock-free single-producer, single-consumer ring of mono samples for the headphone monitor (#233).
///
/// The input callback writes; the output callback reads. Storage is allocated once. Neither side allocates, locks or
/// waits (ADR 0002), and the monitor never holds up the input: a block that doesn't fit is dropped whole, and a read
/// that finds too little plays silence for the rest.
public final class MonitorRing: @unchecked Sendable {
    public let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Float>
    /// Total frames ever written and read. Only the producer stores `written`, only the consumer `read`.
    private let written = Atomic<Int>(0)
    private let readCount = Atomic<Int>(0)
    private let overrun = Atomic<Int>(0)
    private let underrun = Atomic<Int>(0)
    private let skipped = Atomic<Int>(0)

    /// - Parameter capacity: a power of two, in frames.
    public init(capacity: Int) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0, "capacity must be a power of two")
        self.capacity = capacity
        mask = capacity - 1
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit { storage.deallocate() }

    /// Frames dropped because a block didn't fit.
    public var overrunFrames: Int { overrun.load(ordering: .relaxed) }
    /// Frames played as silence because the ring ran short.
    public var underrunFrames: Int { underrun.load(ordering: .relaxed) }
    /// Frames passed over so the monitor doesn't fall further behind than its latency limit.
    public var skippedFrames: Int { skipped.load(ordering: .relaxed) }

    /// Frames waiting to be read.
    public var availableFrames: Int { written.load(ordering: .acquiring) - readCount.load(ordering: .acquiring) }

    /// Producer (the input callback). Real-time safe. Stores `count` samples, or drops them all when they don't fit.
    public func write(_ samples: UnsafePointer<Float>, count: Int) {
        let w = written.load(ordering: .relaxed)
        let r = readCount.load(ordering: .acquiring)
        guard count <= capacity - (w - r) else {
            overrun.add(count, ordering: .relaxed)
            return
        }
        let start = w & mask
        let first = min(count, capacity - start)
        (storage + start).update(from: samples, count: first)
        if first < count { storage.update(from: samples + first, count: count - first) }
        written.store(w + count, ordering: .releasing)
    }

    /// Consumer. Real-time safe. Passes over everything waiting, so nothing old plays when the monitor comes back on.
    public func drain() {
        readCount.store(written.load(ordering: .acquiring), ordering: .releasing)
    }

    /// Consumer (the output callback). Real-time safe. Fills `out` with `count` samples, silence where the ring runs
    /// short. When more than `latencyLimit` frames would still be waiting after this read, the oldest are skipped.
    public func read(into out: UnsafeMutablePointer<Float>, count: Int, latencyLimit: Int) {
        var r = readCount.load(ordering: .relaxed)
        let available = written.load(ordering: .acquiring) - r
        // Compared without subtracting, so an unbounded limit (`.max`) can't overflow.
        let excess = available - count > latencyLimit ? available - count - latencyLimit : 0
        if excess > 0 {
            r += excess
            skipped.add(excess, ordering: .relaxed)
        }
        let n = min(count, available - excess)
        let start = r & mask
        let first = min(n, capacity - start)
        out.update(from: storage + start, count: first)
        if first < n { (out + first).update(from: storage, count: n - first) }
        if n < count {
            (out + n).update(repeating: 0, count: count - n)
            underrun.add(count - n, ordering: .relaxed)
        }
        readCount.store(r + n, ordering: .releasing)
    }
}

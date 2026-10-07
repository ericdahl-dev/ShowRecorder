import AudioIO
import Synchronization

/// A lock-free single-producer, single-consumer ring of planar samples.
///
/// The real-time thread writes; the writer thread reads. Storage is allocated once.
/// `write` never allocates, locks or blocks (ADR 0002).
final class SampleRing: @unchecked Sendable {
    let channelCount: Int
    let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    /// Total frames ever written and read. Only the producer stores `written`, only the consumer `read`.
    private let written = Atomic<Int>(0)
    private let read = Atomic<Int>(0)
    /// The Take frame this ring's Copy starts at: 0 for a Copy there from the start, later for one that
    /// joined mid-Take, -1 until the real-time thread has set it.
    let joinFrame = Atomic<Int>(-1)
    /// Frames dropped because the ring was full.
    let overflowedFrames = Atomic<Int>(0)

    /// A stretch the ring had no room for: it fell after `storedFrames` frames had been stored, and was
    /// `length` frames long.
    struct Drop: Equatable, Sendable {
        var storedFrames: Int
        var length: Int
    }

    private let dropCapacity: Int
    /// Two Ints per logged drop: where it fell and how long it was.
    private let dropStorage: UnsafeMutablePointer<Int>
    /// Drops logged and read. Only the producer stores the first, only the consumer the second.
    private let dropsLogged = Atomic<Int>(0)
    private let dropsRead = Atomic<Int>(0)
    /// Frames dropped while the log was full: kept as a total, without a position, so none are lost.
    private let unloggedDroppedFrames = Atomic<Int>(0)

    init(channelCount: Int, capacity: Int, dropLogCapacity: Int = 256) {
        self.channelCount = channelCount
        self.capacity = capacity
        dropCapacity = dropLogCapacity
        dropStorage = .allocate(capacity: dropLogCapacity * 2)
        dropStorage.initialize(repeating: 0, count: dropLogCapacity * 2)
        storage = .allocate(capacity: max(channelCount, 1) * capacity)
        storage.initialize(repeating: 0, count: max(channelCount, 1) * capacity)
    }

    deinit {
        storage.deallocate()
        dropStorage.deallocate()
    }

    /// Frames ever written (not counting dropped blocks). Read from any thread.
    var totalWrittenFrames: Int {
        written.load(ordering: .acquiring)
    }

    var availableFrames: Int {
        written.load(ordering: .acquiring) - read.load(ordering: .relaxed)
    }

    /// Producer: copies a block in. Drops the block and counts it if there isn't room. Real-time safe.
    func write(_ block: AudioBlock) {
        let frames = block.frameCount
        let start = written.load(ordering: .relaxed)
        guard capacity - (start - read.load(ordering: .acquiring)) >= frames else {
            overflowedFrames.add(frames, ordering: .relaxed)
            logDrop(storedFrames: start, length: frames)
            return
        }
        let channels = min(channelCount, block.channelCount)
        for channel in 0..<channels {
            let source = block.channels[channel]
            let base = storage + channel * capacity
            let offset = start % capacity
            let first = min(frames, capacity - offset)
            (base + offset).update(from: source, count: first)
            if first < frames {
                base.update(from: source + first, count: frames - first)
            }
        }
        written.store(start + frames, ordering: .releasing)
    }

    /// Producer: remembers a dropped block. Real-time safe.
    private func logDrop(storedFrames: Int, length: Int) {
        let logged = dropsLogged.load(ordering: .relaxed)
        if logged > 0 {
            // Nothing stored since the last drop: the same stretch. The consumer can't have it yet (it waits
            // for stored audio after it), so extending it here is safe.
            let last = dropStorage + ((logged - 1) % dropCapacity) * 2
            if last[0] == storedFrames {
                last[1] += length
                return
            }
        }
        guard logged - dropsRead.load(ordering: .acquiring) < dropCapacity else {
            unloggedDroppedFrames.add(length, ordering: .relaxed)
            return
        }
        let slot = dropStorage + (logged % dropCapacity) * 2
        slot[0] = storedFrames
        slot[1] = length
        dropsLogged.store(logged + 1, ordering: .releasing)
    }

    /// Consumer: the oldest drop not yet consumed, once it is over: audio has been stored after it, so no
    /// more of it can be added. With `final` (the producer has stopped) the last drop counts as over too.
    /// Call `consumeDrop()` when it has been dealt with.
    func nextDrop(final: Bool = false) -> Drop? {
        let read = dropsRead.load(ordering: .relaxed)
        guard read < dropsLogged.load(ordering: .acquiring) else { return nil }
        let slot = dropStorage + (read % dropCapacity) * 2
        let drop = Drop(storedFrames: slot[0], length: slot[1])
        guard final || written.load(ordering: .acquiring) > drop.storedFrames else { return nil }
        return drop
    }

    /// Consumer: frames dropped that didn't fit in the log, once. Their position isn't known.
    func takeUnloggedDroppedFrames() -> Int {
        unloggedDroppedFrames.exchange(0, ordering: .acquiringAndReleasing)
    }

    /// Consumer: the drop `nextDrop()` returned has been dealt with.
    func consumeDrop() {
        dropsRead.store(dropsRead.load(ordering: .relaxed) + 1, ordering: .releasing)
    }

    /// Consumer: hands up to `maxFrames` of each channel to `body` (in up to two contiguous pieces)
    /// and then releases them. Returns the number of frames consumed.
    @discardableResult
    func consume(maxFrames: Int, _ body: (_ channel: Int, _ samples: UnsafeBufferPointer<Float>) throws -> Void) rethrows -> Int {
        let start = read.load(ordering: .relaxed)
        let frames = min(maxFrames, written.load(ordering: .acquiring) - start)
        guard frames > 0 else { return 0 }
        let offset = start % capacity
        let first = min(frames, capacity - offset)
        for channel in 0..<channelCount {
            let base = UnsafePointer(storage + channel * capacity)
            try body(channel, UnsafeBufferPointer(start: base + offset, count: first))
            if first < frames {
                try body(channel, UnsafeBufferPointer(start: base, count: frames - first))
            }
        }
        read.store(start + frames, ordering: .releasing)
        return frames
    }

    /// Consumer: discards everything currently in the ring.
    func discardAll() {
        read.store(written.load(ordering: .acquiring), ordering: .releasing)
    }
}

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
    /// Frames dropped because the ring was full.
    let overflowedFrames = Atomic<Int>(0)

    init(channelCount: Int, capacity: Int) {
        self.channelCount = channelCount
        self.capacity = capacity
        storage = .allocate(capacity: max(channelCount, 1) * capacity)
        storage.initialize(repeating: 0, count: max(channelCount, 1) * capacity)
    }

    deinit { storage.deallocate() }

    var availableFrames: Int {
        written.load(ordering: .acquiring) - read.load(ordering: .relaxed)
    }

    /// Producer: copies a block in. Drops the block and counts it if there isn't room. Real-time safe.
    func write(_ block: AudioBlock) {
        let frames = block.frameCount
        let start = written.load(ordering: .relaxed)
        guard capacity - (start - read.load(ordering: .acquiring)) >= frames else {
            overflowedFrames.add(frames, ordering: .relaxed)
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

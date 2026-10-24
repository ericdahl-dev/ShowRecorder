import AudioIO
import Synchronization

/// A rolling buffer of the most recent audio: it holds up to `capacity` frames of every channel and
/// overwrites the oldest. The real-time thread writes; any other thread can `read` a range of frames
/// while writing carries on.
///
/// `write` never allocates, locks or blocks (ADR 0002). It is single-producer: only one thread writes.
///
/// A read may copy frames the writer overwrites while it copies. The writer announces how far it is
/// about to write (`writing`) before it touches the storage, and the reader checks that mark after
/// copying and refuses the read if any frames may have been overwritten. So a read is never torn; when
/// the writer laps the reader it returns nil instead.
final class PreRollBuffer: @unchecked Sendable {
    let channelCount: Int
    let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    /// Frames fully written. Only the producer stores it.
    private let written = Atomic<Int>(0)
    /// Frames written or being written: `written` plus the block in progress.
    private let writing = Atomic<Int>(0)

    init(channelCount: Int, capacity: Int) {
        self.channelCount = channelCount
        self.capacity = max(capacity, 1)
        storage = .allocate(capacity: max(channelCount, 1) * self.capacity)
        storage.initialize(repeating: 0, count: max(channelCount, 1) * self.capacity)
    }

    deinit { storage.deallocate() }

    /// Frames ever written. Read from any thread.
    var totalWrittenFrames: Int { written.load(ordering: .acquiring) }

    /// Producer: copies a block in, overwriting the oldest audio. A block longer than the buffer leaves
    /// its last `capacity` frames. Real-time safe.
    func write(_ block: AudioBlock) {
        let frames = block.frameCount
        let start = written.load(ordering: .relaxed)
        writing.store(start + frames, ordering: .releasing)
        // The mark must be visible before any storage is touched.
        atomicMemoryFence(ordering: .sequentiallyConsistent)
        let skip = max(0, frames - capacity)
        let kept = frames - skip
        let offset = (start + skip) % capacity
        let first = min(kept, capacity - offset)
        for channel in 0..<min(channelCount, block.channelCount) {
            let source = block.channels[channel] + skip
            let base = storage + channel * capacity
            (base + offset).update(from: source, count: first)
            if first < kept { base.update(from: source + first, count: kept - first) }
        }
        written.store(start + frames, ordering: .releasing)
    }

    /// Exactly the frames `range` (counted from the first frame ever written) of every channel, or nil if
    /// they aren't all there: not written yet, or already overwritten (including while this was copying).
    func read(frames range: Range<Int>) -> [[Float]]? {
        let count = range.count
        guard range.lowerBound >= 0, count <= capacity, range.upperBound <= written.load(ordering: .acquiring) else { return nil }
        var channels = (0..<channelCount).map { _ in [Float](repeating: 0, count: count) }
        if count > 0 {
            let offset = range.lowerBound % capacity
            let first = min(count, capacity - offset)
            for channel in 0..<channelCount {
                let base = UnsafePointer(storage + channel * capacity)
                channels[channel].withUnsafeMutableBufferPointer { out in
                    out.baseAddress!.update(from: base + offset, count: first)
                    if first < count { (out.baseAddress! + first).update(from: base, count: count - first) }
                }
            }
        }
        atomicMemoryFence(ordering: .sequentiallyConsistent)
        return writing.load(ordering: .acquiring) - capacity <= range.lowerBound ? channels : nil
    }
}

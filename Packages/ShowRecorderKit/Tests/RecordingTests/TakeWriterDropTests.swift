import AudioIO
import BroadcastWave
import Foundation
@testable import Recording
import Synchronization
import Testing

/// A Copy's writer puts silence where its ring had to drop audio, so the Stems stay as long as the Take.
@Suite("Dropouts in the writer")
struct TakeWriterDropTests {
    /// A Stem in memory. The first `append` waits on `gate` when one is given, which holds the writer with
    /// the ring still full so a test can overfill it on purpose.
    final class MemoryStem: StemSink, @unchecked Sendable {
        private let lock = NSLock()
        private var _samples: [Float] = []
        let gate: DispatchSemaphore?
        private var gated: Bool
        init(gate: DispatchSemaphore? = nil) {
            self.gate = gate
            gated = gate != nil
        }
        var samples: [Float] { lock.withLock { _samples } }
        var frameCount: UInt64 { UInt64(samples.count) }
        func append(_ new: UnsafeBufferPointer<Float>) throws {
            if gated {
                gated = false
                gate?.wait()
            }
            lock.withLock { _samples += new }
        }
        func commitHeader() throws {}
        func finalize() throws {}
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { markers.count }
    }

    /// Writes the ramp `start..<start+count` into `ring` as one block.
    func write(_ ring: SampleRing, from start: Int, count: Int) {
        var samples = (0..<count).map { Float(start + $0) }
        samples.withUnsafeMutableBufferPointer { buffer in
            var pointer = UnsafePointer(buffer.baseAddress!)
            withUnsafePointer(to: &pointer) {
                ring.write(AudioBlock(channels: $0, channelCount: 1, frameCount: count, hostTime: 0))
            }
        }
    }

    func waitUntil(_ condition: () -> Bool) {
        for _ in 0..<1_000 where !condition() { Thread.sleep(forTimeInterval: 0.002) }
    }

    @Test("A dropped block becomes silence of exactly its length, between the audio before and after it")
    func silenceWhereAudioWasLost() {
        let ring = SampleRing(channelCount: 1, capacity: 1_000)
        let gate = DispatchSemaphore(value: 0)
        let stem = MemoryStem(gate: gate)
        let writer = TakeWriter(ring: ring, stems: [stem], commitInterval: 48_000)
        ring.joinFrame.store(0, ordering: .releasing)
        write(ring, from: 0, count: 800)
        writer.start()
        waitUntil { ring.availableFrames == 800 }  // the writer is holding at its first append

        write(ring, from: 800, count: 300)  // no room: dropped
        gate.signal()
        waitUntil { ring.availableFrames == 0 }
        write(ring, from: 1_100, count: 100)  // stored after the drop
        writer.stop()

        let expected = (0..<800).map(Float.init) + [Float](repeating: 0, count: 300) + (1_100..<1_200).map(Float.init)
        #expect(stem.samples == expected)
    }

    @Test("A drop at the very end of the Take, with nothing stored after it, is still written when the Take stops")
    func dropAtTheEnd() {
        let ring = SampleRing(channelCount: 1, capacity: 10_000)
        let gate = DispatchSemaphore(value: 0)
        let stem = MemoryStem(gate: gate)
        let writer = TakeWriter(ring: ring, stems: [stem], commitInterval: 48_000)
        ring.joinFrame.store(0, ordering: .releasing)
        write(ring, from: 0, count: 8_000)
        writer.start()
        waitUntil { ring.availableFrames == 8_000 }

        write(ring, from: 8_000, count: 9_000)  // more than the 2,000 free: dropped, and it's the last thing
        gate.signal()
        writer.stop()

        // 9,000 frames of silence is more than one chunk of the writer's silence buffer.
        #expect(stem.samples == (0..<8_000).map(Float.init) + [Float](repeating: 0, count: 9_000))
    }

    @Test("Drops that didn't fit in the log still become silence, at the end, so the Stem is as long as the Take")
    func unloggedDropsBecomeSilenceAtTheEnd() {
        // A log with room for one drop, and the drops made before the writer starts.
        let ring = SampleRing(channelCount: 1, capacity: 1_000, dropLogCapacity: 1)
        write(ring, from: 0, count: 800)
        write(ring, from: 800, count: 300)  // drop A (logged)
        ring.consume(maxFrames: 800) { _, _ in }
        write(ring, from: 1_100, count: 900)
        write(ring, from: 2_000, count: 300)  // drop B: the log is full, so only its length is kept
        #expect(ring.overflowedFrames.load(ordering: .relaxed) == 600)

        let stem = MemoryStem()
        let writer = TakeWriter(ring: ring, stems: [stem], commitInterval: 48_000)
        ring.joinFrame.store(0, ordering: .releasing)
        writer.start()
        writer.stop()

        #expect(stem.samples == [Float](repeating: 0, count: 300) + (1_100..<2_000).map(Float.init) + [Float](repeating: 0, count: 300))
    }
}

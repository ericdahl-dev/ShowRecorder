import AudioIO
@testable import Recording
import Testing

/// What the ring remembers about blocks it had no room for.
@Suite("Ring drop log")
struct SampleRingDropTests {
    /// Writes one block of `frames` frames into `ring`.
    func write(_ frames: Int, to ring: SampleRing) {
        var samples = [Float](repeating: 0.5, count: frames)
        samples.withUnsafeMutableBufferPointer { buffer in
            var pointer = UnsafePointer(buffer.baseAddress!)
            withUnsafePointer(to: &pointer) {
                ring.write(AudioBlock(channels: $0, channelCount: 1, frameCount: frames, hostTime: 0))
            }
        }
    }

    /// Reads and discards `frames` frames, to make room.
    func drain(_ frames: Int, from ring: SampleRing) {
        ring.consume(maxFrames: frames) { _, _ in }
    }

    @Test("A dropped block is logged with where it fell in the stored stream and how long it was")
    func oneDrop() {
        let ring = SampleRing(channelCount: 1, capacity: 1_000)
        write(800, to: ring)
        write(300, to: ring)  // no room: dropped
        drain(800, from: ring)
        write(100, to: ring)  // stored after the drop

        #expect(ring.nextDrop() == SampleRing.Drop(storedFrames: 800, length: 300))
    }

    @Test("A drop isn't handed over until audio has been stored after it, since more of it may still be dropped")
    func notUntilLaterAudioIsStored() {
        let ring = SampleRing(channelCount: 1, capacity: 1_000)
        write(800, to: ring)
        write(300, to: ring)  // dropped
        #expect(ring.nextDrop() == nil, "the drop may still be going on")

        drain(800, from: ring)
        #expect(ring.nextDrop() == nil, "nothing stored since")
        write(100, to: ring)
        #expect(ring.nextDrop() != nil)
    }

    @Test("Blocks dropped one after another are one drop; the last one is available once the producer has stopped")
    func backToBackMerge() {
        let ring = SampleRing(channelCount: 1, capacity: 1_000)
        write(800, to: ring)
        write(300, to: ring)
        write(250, to: ring)
        write(250, to: ring)  // three blocks in a row, none fits in the 200 frames left
        #expect(ring.nextDrop(final: true) == SampleRing.Drop(storedFrames: 800, length: 800))
        #expect(ring.overflowedFrames.load(ordering: .relaxed) == 800)
    }

    @Test("Drops with audio stored between them stay separate and come back in order as they're consumed")
    func separateDropsInOrder() {
        let ring = SampleRing(channelCount: 1, capacity: 1_000)
        write(800, to: ring)
        write(300, to: ring)  // drop A, after 800 stored
        drain(800, from: ring)
        write(900, to: ring)  // 1,700 stored in all
        write(300, to: ring)  // drop B, after 1,700 stored

        #expect(ring.nextDrop() == SampleRing.Drop(storedFrames: 800, length: 300))
        ring.consumeDrop()
        #expect(ring.nextDrop() == nil, "B is still going: nothing stored after it yet")

        drain(900, from: ring)
        write(50, to: ring)
        #expect(ring.nextDrop() == SampleRing.Drop(storedFrames: 1_700, length: 300))
        ring.consumeDrop()
        #expect(ring.nextDrop() == nil)
        #expect(ring.nextDrop(final: true) == nil)
        #expect(ring.overflowedFrames.load(ordering: .relaxed) == 600)
    }

    @Test("When the log is full the lost frames still add up exactly; the extra detail is only a total")
    func fullLog() {
        let ring = SampleRing(channelCount: 1, capacity: 1_000, dropLogCapacity: 2)
        write(900, to: ring)
        // Three separate drops, with a little audio stored between each (the reader keeps up with the audio only).
        for _ in 0..<3 {
            write(200, to: ring)  // dropped: 100 free
            drain(900, from: ring)
            write(900, to: ring)
        }
        #expect(ring.overflowedFrames.load(ordering: .relaxed) == 600)

        var logged = 0
        while let drop = ring.nextDrop() {
            logged += drop.length
            ring.consumeDrop()
        }
        #expect(logged == 400, "two drops fit the log")
        #expect(ring.takeUnloggedDroppedFrames() == 200, "the third is kept as a total")
        #expect(ring.takeUnloggedDroppedFrames() == 0, "and handed over once")
    }

    @Test("Discarding the ring forgets its drops too, so the next Take doesn't inherit them")
    func discardForgetsDrops() {
        let ring = SampleRing(channelCount: 1, capacity: 1_000, dropLogCapacity: 1)
        write(800, to: ring)
        write(300, to: ring)  // logged
        drain(800, from: ring)
        write(900, to: ring)
        write(300, to: ring)  // not logged: the log is full

        ring.discardAll()
        #expect(ring.nextDrop(final: true) == nil)
        #expect(ring.takeUnloggedDroppedFrames() == 0)
    }
}

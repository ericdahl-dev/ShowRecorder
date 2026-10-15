@testable import AudioIO
import Testing

/// The headphone monitor's ring (#233): fed from the input callback, played from the output callback. It never holds
/// up the input: when full it drops the newest block, and when empty it plays silence.
@Suite("Monitor ring")
struct MonitorRingTests {
    func write(_ ring: MonitorRing, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) }
    }

    func read(_ ring: MonitorRing, _ count: Int, latencyLimit: Int = .max) -> [Float] {
        var out = [Float](repeating: -1, count: count)
        out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: count, latencyLimit: latencyLimit) }
        return out
    }

    @Test("What goes in comes out in order, across the end of the ring")
    func roundTripAndWrap() {
        let ring = MonitorRing(capacity: 8)
        write(ring, [1, 2, 3, 4, 5, 6])
        #expect(read(ring, 6) == [1, 2, 3, 4, 5, 6])
        write(ring, [7, 8, 9, 10, 11])                        // wraps
        #expect(ring.availableFrames == 5)
        #expect(read(ring, 5) == [7, 8, 9, 10, 11])
        #expect(ring.overrunFrames == 0 && ring.underrunFrames == 0)
    }

    @Test("A block that doesn't fit is dropped whole and counted; what was there plays on untouched")
    func overrunDropsTheNewestBlock() {
        let ring = MonitorRing(capacity: 8)
        write(ring, [1, 2, 3, 4, 5, 6])
        write(ring, [7, 8, 9])                                // only 2 free: dropped
        #expect(ring.overrunFrames == 3)
        #expect(ring.availableFrames == 6)
        #expect(read(ring, 6) == [1, 2, 3, 4, 5, 6])
        write(ring, [7, 8, 9])                                // room again
        #expect(read(ring, 3) == [7, 8, 9])
    }

    @Test("Reading more than is there plays what there is, then silence, and counts the shortfall")
    func underrunPlaysSilence() {
        let ring = MonitorRing(capacity: 8)
        write(ring, [1, 2])
        #expect(read(ring, 5) == [1, 2, 0, 0, 0])
        #expect(ring.underrunFrames == 3)
        #expect(read(ring, 2) == [0, 0])
        #expect(ring.underrunFrames == 5)
    }

    @Test("When more than the latency limit is waiting beyond this read, the oldest audio is skipped to catch up")
    func skipsAheadToBoundLatency() {
        let ring = MonitorRing(capacity: 16)
        write(ring, (1...12).map(Float.init))
        // Reading 2 with at most 4 left waiting afterwards: 12 - 2 - 4 = 6 oldest frames are skipped.
        #expect(read(ring, 2, latencyLimit: 4) == [7, 8])
        #expect(ring.skippedFrames == 6)
        #expect(ring.availableFrames == 4)
        #expect(read(ring, 4, latencyLimit: 4) == [9, 10, 11, 12])
    }
}

import AudioIO
import Foundation
@testable import Recording
import Synchronization
import Testing

@Suite("Pre-roll buffer")
struct PreRollBufferTests {
    /// Writes `count` frames whose value is the frame's absolute index plus `channel * 1_000_000`,
    /// starting at absolute frame `start`, in blocks of `block` frames.
    func write(_ buffer: PreRollBuffer, from start: Int, count: Int, block: Int = 480, channels: Int = 2) {
        var frame = start
        while frame < start + count {
            let n = min(block, start + count - frame)
            var planes = (0..<channels).map { channel in (0..<n).map { Float(frame + $0 + channel * 1_000_000) } }
            let pointers = planes.indices.map { index in
                planes[index].withUnsafeMutableBufferPointer { UnsafePointer($0.baseAddress!) }
            }
            pointers.withUnsafeBufferPointer {
                buffer.write(AudioBlock(channels: $0.baseAddress!, channelCount: channels, frameCount: n, hostTime: 0))
            }
            frame += n
        }
    }

    func expected(channel: Int, from start: Int, count: Int) -> [Float] {
        (0..<count).map { Float(start + $0 + channel * 1_000_000) }
    }

    @Test("A range that is not all written yet is refused")
    func notWrittenYet() {
        let buffer = PreRollBuffer(channelCount: 2, capacity: 1_000)
        #expect(buffer.read(frames: 0..<50) == nil)
        write(buffer, from: 0, count: 300)
        #expect(buffer.read(frames: 0..<300)?[0] == expected(channel: 0, from: 0, count: 300))
        #expect(buffer.read(frames: 0..<700) == nil)
    }

    @Test("A block larger than the buffer leaves its last frames")
    func blockLargerThanBuffer() {
        let buffer = PreRollBuffer(channelCount: 1, capacity: 100)
        write(buffer, from: 0, count: 250, block: 250, channels: 1)
        #expect(buffer.read(frames: 150..<250)?[0] == expected(channel: 0, from: 150, count: 100))
        #expect(buffer.read(frames: 149..<249) == nil)
    }

    final class Flag: @unchecked Sendable {
        let done = Atomic<Bool>(false)
    }

    @Test("A read taken while the writer keeps going is never torn")
    func concurrentWriter() async throws {
        let buffer = PreRollBuffer(channelCount: 1, capacity: 20_000)
        let flag = Flag()
        let writer = Thread {
            var frame = 0
            // Float holds integers exactly up to 2^24, so the ramp stays checkable.
            while frame < 10_000_000 {
                var samples = (0..<480).map { Float(frame + $0) }
                samples.withUnsafeMutableBufferPointer { storage in
                    var pointer = UnsafePointer(storage.baseAddress!)
                    withUnsafePointer(to: &pointer) {
                        buffer.write(AudioBlock(channels: $0, channelCount: 1, frameCount: 480, hostTime: 0))
                    }
                }
                frame += 480
                Thread.sleep(forTimeInterval: 0.00005)
            }
            flag.done.store(true, ordering: .releasing)
        }
        writer.start()

        var reads = 0
        var torn = 0
        while !flag.done.load(ordering: .acquiring) {
            let end = buffer.totalWrittenFrames
            let start = max(0, end - 19_500)   // about one block short of the capacity: the writer often laps a read
            // Nil when the writer lapped this read; what comes back must be the ramp, whole.
            if let samples = buffer.read(frames: start..<end)?[0], !samples.isEmpty {
                reads += 1
                if samples.enumerated().contains(where: { $1 != Float(start + $0) }) { torn += 1 }
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(reads > 50)
        #expect(torn == 0)
    }
}

extension PreRollBufferTests {
    @Test("An exact range reads back exactly, and is refused when not all of it is there")
    func readRange() {
        let buffer = PreRollBuffer(channelCount: 2, capacity: 1_000)
        write(buffer, from: 0, count: 2_750)

        #expect(buffer.read(frames: 2_000..<2_300)?[0] == expected(channel: 0, from: 2_000, count: 300))
        #expect(buffer.read(frames: 2_000..<2_300)?[1] == expected(channel: 1, from: 2_000, count: 300))
        #expect(buffer.read(frames: 1_750..<2_750)?[0] == expected(channel: 0, from: 1_750, count: 1_000))
        #expect(buffer.read(frames: 1_749..<2_749) == nil)  // overwritten
        #expect(buffer.read(frames: 2_700..<2_800) == nil)  // not written yet
        #expect(buffer.read(frames: 0..<1_001) == nil)  // longer than the buffer
        #expect(buffer.read(frames: 2_100..<2_100)?.count == 2)
    }
}

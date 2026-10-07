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

    @Test("It returns the most recent N frames, exactly, across a wrap")
    func lastFramesAcrossWrap() {
        let buffer = PreRollBuffer(channelCount: 2, capacity: 1_000)
        write(buffer, from: 0, count: 2_750)
        let snapshot = buffer.snapshot(maxFrames: 700)

        #expect(snapshot.startFrame == 2_050)
        #expect(snapshot.channels.count == 2)
        #expect(snapshot.channels[0] == expected(channel: 0, from: 2_050, count: 700))
        #expect(snapshot.channels[1] == expected(channel: 1, from: 2_050, count: 700))
    }

    @Test("It returns less when less has been written")
    func shorterThanRequested() {
        let buffer = PreRollBuffer(channelCount: 2, capacity: 1_000)
        write(buffer, from: 0, count: 300)
        let snapshot = buffer.snapshot(maxFrames: 700)

        #expect(snapshot.startFrame == 0)
        #expect(snapshot.channels[0] == expected(channel: 0, from: 0, count: 300))
        #expect(buffer.snapshot(maxFrames: 100).startFrame == 200)
    }

    @Test("It never returns more than it can hold")
    func cappedAtCapacity() {
        let buffer = PreRollBuffer(channelCount: 1, capacity: 500)
        write(buffer, from: 0, count: 2_000, channels: 1)
        let snapshot = buffer.snapshot(maxFrames: 10_000)
        #expect(snapshot.channels[0] == expected(channel: 0, from: 1_500, count: 500))
        #expect(snapshot.startFrame == 1_500)
    }

    @Test("A block larger than the buffer leaves its last frames")
    func blockLargerThanBuffer() {
        let buffer = PreRollBuffer(channelCount: 1, capacity: 100)
        write(buffer, from: 0, count: 250, block: 250, channels: 1)
        let snapshot = buffer.snapshot(maxFrames: 100)
        #expect(snapshot.startFrame == 150)
        #expect(snapshot.channels[0] == expected(channel: 0, from: 150, count: 100))
    }

    @Test("Asking for nothing, or from an empty buffer, returns nothing")
    func zeroAndEmpty() {
        let buffer = PreRollBuffer(channelCount: 2, capacity: 100)
        #expect(buffer.snapshot(maxFrames: 50).channels.allSatisfy { $0.isEmpty })
        write(buffer, from: 0, count: 80)
        let none = buffer.snapshot(maxFrames: 0)
        #expect(none.channels.count == 2)
        #expect(none.channels.allSatisfy { $0.isEmpty })
    }

    final class Flag: @unchecked Sendable {
        let done = Atomic<Bool>(false)
    }

    @Test("A snapshot taken while the writer keeps going is never torn")
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

        var snapshots = 0
        var torn = 0
        while !flag.done.load(ordering: .acquiring) {
            let snapshot = buffer.snapshot(maxFrames: 20_000)
            let samples = snapshot.channels[0]
            if !samples.isEmpty {
                snapshots += 1
                if samples.enumerated().contains(where: { $1 != Float(snapshot.startFrame + $0) }) { torn += 1 }
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(snapshots > 50)
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

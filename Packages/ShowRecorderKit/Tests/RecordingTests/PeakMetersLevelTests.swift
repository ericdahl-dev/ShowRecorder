import Foundation
import AudioIO
import Testing

@testable import Recording

/// What the audio thread keeps for the VU meter: the average rectified level beside the peak.
@Suite("Meter levels")
struct PeakMetersLevelTests {
    static func record(_ samples: [Float], into meters: PeakMeters, channels: Int = 1) {
        let buffers = (0..<channels).map { _ -> UnsafeMutablePointer<Float> in
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
            buffer.initialize(from: samples, count: samples.count)
            return buffer
        }
        defer { buffers.forEach { $0.deallocate() } }
        var pointers = buffers.map { UnsafePointer<Float>($0) }
        pointers.withUnsafeMutableBufferPointer {
            meters.record(AudioBlock(channels: $0.baseAddress!, channelCount: channels, frameCount: samples.count, hostTime: 0))
        }
    }

    @Test("A read returns the peak, the mean rectified level and the frame count since the last read, then resets")
    func readsAndResets() {
        let meters = PeakMeters(channelCount: 1)
        Self.record([Float](repeating: 0.5, count: 480), into: meters)
        Self.record([Float](repeating: -0.25, count: 480), into: meters)
        let first = meters.takeLevels()
        #expect(first.count == 1)
        #expect(first[0].peak == 0.5)
        #expect(first[0].frames == 960)
        #expect(abs(first[0].meanRectified - 0.375) < 1e-6)
        let second = meters.takeLevels()
        #expect(second[0].frames == 0 && second[0].peak == 0 && second[0].meanRectified == 0)
    }

    @Test("Many small blocks give the same levels as one large block; a sine's mean is 2/pi of its peak")
    func smallBlocksAddUp() {
        let sine = (0..<4800).map { Float(0.8 * sin(2 * Double.pi * 10 * Double($0) / 4800)) }
        let whole = PeakMeters(channelCount: 2)
        Self.record(sine, into: whole, channels: 2)
        let pieces = PeakMeters(channelCount: 2)
        for start in stride(from: 0, to: sine.count, by: 160) {
            Self.record(Array(sine[start..<start + 160]), into: pieces, channels: 2)
        }
        let a = whole.takeLevels(), b = pieces.takeLevels()
        for channel in 0..<2 {
            #expect(a[channel].frames == 4800 && b[channel].frames == 4800)
            #expect(abs(a[channel].meanRectified - Float(0.8 * 2 / Double.pi)) < 1e-4)
            #expect(abs(a[channel].meanRectified - b[channel].meanRectified) < 1e-5)
            #expect(a[channel].peak == b[channel].peak)
        }
    }

    @Test("A producer and a reader at the same time lose no frames and count none twice")
    func concurrentReads() async {
        let meters = PeakMeters(channelCount: 1)
        let blocks = 20_000, framesPerBlock = 100
        let producer = Task.detached {
            let samples = [Float](repeating: 0.5, count: framesPerBlock)
            for _ in 0..<blocks { Self.record(samples, into: meters) }
        }
        var frames = 0
        var weighted = 0.0
        while !producer.isCancelled {
            let level = meters.takeLevels()[0]
            frames += level.frames
            weighted += Double(level.meanRectified) * Double(level.frames)
            if frames >= blocks * framesPerBlock { break }
            await Task.yield()
        }
        await producer.value
        let rest = meters.takeLevels()[0]
        frames += rest.frames
        weighted += Double(rest.meanRectified) * Double(rest.frames)
        #expect(frames == blocks * framesPerBlock)
        #expect(abs(weighted / Double(frames) - 0.5) < 1e-3)
    }
}

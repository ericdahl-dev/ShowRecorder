import Accelerate
import AudioIO
import Synchronization

/// One channel's levels over the time since the last read.
struct ChannelLevel: Equatable {
    /// Largest magnitude, 0...1 of full scale.
    var peak: Float
    /// Average of the magnitudes, 0...1 of full scale; 0 when there were no frames.
    var meanRectified: Float
    var frames: Int
}

/// Per-USB-Channel levels (peak, and the average rectified level for the VU meter), written on the
/// real-time thread and read by the UI.
///
/// Storage is allocated once, when the recorder is Armed. `record(_:)` is real-time safe:
/// no allocation, no locks, only relaxed atomics (ADR 0002).
final class PeakMeters: @unchecked Sendable {
    let channelCount: Int
    /// Linear peak magnitudes, stored as `Float` bit patterns.
    private let peaks: UnsafeMutablePointer<Atomic<UInt32>>
    /// Per channel, the sum of the magnitudes (`Float` bits, high half) and the frame count (low half)
    /// in one word, so a read takes both together and they never come from different moments.
    private let sums: UnsafeMutablePointer<Atomic<UInt64>>

    init(channelCount: Int) {
        self.channelCount = channelCount
        peaks = .allocate(capacity: max(channelCount, 1))
        sums = .allocate(capacity: max(channelCount, 1))
        for channel in 0..<channelCount {
            (peaks + channel).initialize(to: Atomic(0))
            (sums + channel).initialize(to: Atomic(0))
        }
    }

    deinit {
        peaks.deinitialize(count: channelCount)
        peaks.deallocate()
        sums.deinitialize(count: channelCount)
        sums.deallocate()
    }

    /// Raises each channel's peak to the largest magnitude in the block. Real-time safe.
    func record(_ block: AudioBlock) {
        for channel in 0..<min(channelCount, block.channelCount) {
            // One C call: no generic iteration, which in debug builds takes a runtime lock per frame.
            var peak: Float = 0
            vDSP_maxmgv(block.channels[channel], 1, &peak, vDSP_Length(block.frameCount))
            raise(channel, to: peak)
            var mean: Float = 0
            vDSP_meamgv(block.channels[channel], 1, &mean, vDSP_Length(block.frameCount))
            accumulate(channel, sum: mean * Float(block.frameCount), frames: UInt32(truncatingIfNeeded: block.frameCount))
        }
    }

    /// Returns each channel's peak, mean rectified level and frame count since the last call, and resets them.
    func takeLevels() -> [ChannelLevel] {
        (0..<channelCount).map { channel in
            let peak = Float(bitPattern: peaks[channel].exchange(0, ordering: .relaxed))
            let packed = sums[channel].exchange(0, ordering: .relaxed)
            let frames = Int(packed & 0xFFFF_FFFF)
            let sum = Float(bitPattern: UInt32(packed >> 32))
            return ChannelLevel(peak: peak, meanRectified: frames > 0 ? sum / Float(frames) : 0, frames: frames)
        }
    }

    /// Returns each channel's peak since the last call, and resets them.
    func take() -> [Float] {
        (0..<channelCount).map { channel in
            Float(bitPattern: peaks[channel].exchange(0, ordering: .relaxed))
        }
    }

    private func accumulate(_ channel: Int, sum: Float, frames: UInt32) {
        var current = sums[channel].load(ordering: .relaxed)
        while true {
            let total = Float(bitPattern: UInt32(current >> 32)) + sum
            let count = UInt32(truncatingIfNeeded: current) &+ frames
            let desired = UInt64(total.bitPattern) << 32 | UInt64(count)
            let (exchanged, original) = sums[channel].compareExchange(
                expected: current, desired: desired, ordering: .relaxed)
            if exchanged { return }
            current = original
        }
    }

    private func raise(_ channel: Int, to peak: Float) {
        var current = peaks[channel].load(ordering: .relaxed)
        while Float(bitPattern: current) < peak {
            let (exchanged, original) = peaks[channel].compareExchange(
                expected: current, desired: peak.bitPattern, ordering: .relaxed)
            if exchanged { return }
            current = original
        }
    }
}

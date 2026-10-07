import AudioIO
import Synchronization

/// Per-USB-Channel peak levels, written on the real-time thread and read by the UI.
///
/// Storage is allocated once, when the recorder is Armed. `record(_:)` is real-time safe:
/// no allocation, no locks, only relaxed atomics (ADR 0002).
final class PeakMeters: @unchecked Sendable {
    let channelCount: Int
    /// Linear peak magnitudes, stored as `Float` bit patterns.
    private let peaks: UnsafeMutablePointer<Atomic<UInt32>>

    init(channelCount: Int) {
        self.channelCount = channelCount
        peaks = .allocate(capacity: max(channelCount, 1))
        for channel in 0..<channelCount {
            (peaks + channel).initialize(to: Atomic(0))
        }
    }

    deinit {
        peaks.deinitialize(count: channelCount)
        peaks.deallocate()
    }

    /// Raises each channel's peak to the largest magnitude in the block. Real-time safe.
    func record(_ block: AudioBlock) {
        for channel in 0..<min(channelCount, block.channelCount) {
            let samples = block.channels[channel]
            var peak: Float = 0
            for frame in 0..<block.frameCount {
                peak = max(peak, abs(samples[frame]))
            }
            raise(channel, to: peak)
        }
    }

    /// Returns each channel's peak since the last call, and resets them.
    func take() -> [Float] {
        (0..<channelCount).map { channel in
            Float(bitPattern: peaks[channel].exchange(0, ordering: .relaxed))
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

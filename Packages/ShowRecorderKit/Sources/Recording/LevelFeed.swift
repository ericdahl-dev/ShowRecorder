/// The feed auto-gain measures from (#554): every meter tick's windows, so a USB Channel's level is measured in audio
/// time, not on the clock, and a stalled screen can't shorten it. Half a second of audio for the meter to follow a gain
/// move, then the VU reading over the next 2 s, weighted by frames.
@MainActor
public final class LevelFeed {
    /// One measurement under way on a USB Channel.
    private struct Measurement {
        let usbChannel: Int
        let continuation: CheckedContinuation<Double?, Never>
        /// The input's sample rate at its first window.
        var sampleRate: Int?
        /// How many USB Channels the input had at its first window.
        var channels: Int?
        var skipped = 0
        var counted = 0
        var sum = 0.0
    }

    static let settleSeconds = 0.5
    static let measureSeconds = 2.0

    private var measurements: [Int: Measurement] = [:]
    private var nextID = 0
    /// One VU meter per USB Channel, advanced in audio time.
    private var vu: [VUMeter] = []

    public init() {}

    /// A meter tick's windows, one per USB Channel, and the input's sample rate.
    public func meters(_ levels: [ChannelLevel], sampleRate: Int?) {
        // The audio stopped (disarmed): every measurement ends at once, with no level.
        guard let sampleRate else {
            for id in measurements.keys { finish(id, level: nil) }
            return
        }
        if vu.count != levels.count { vu = Array(repeating: VUMeter(), count: levels.count) }
        for (index, level) in levels.enumerated() where level.frames > 0 {
            vu[index].update(meanRectified: Double(level.meanRectified), seconds: Double(level.frames) / Double(sampleRate))
        }
        for (id, var measurement) in measurements {
            let index = measurement.usbChannel - 1
            // The audio stopped (disarmed, or the sample rate or the number of USB Channels changed): it ends at
            // once, with no level.
            guard levels.indices.contains(index), measurement.sampleRate ?? sampleRate == sampleRate,
                  measurement.channels ?? levels.count == levels.count else {
                finish(id, level: nil)
                continue
            }
            measurement.sampleRate = sampleRate
            measurement.channels = levels.count
            let frames = levels[index].frames
            // Whole windows only: one that ends past the half second is still skipped.
            if Double(measurement.skipped) < Self.settleSeconds * Double(sampleRate) {
                measurement.skipped += frames
            } else {
                measurement.sum += vu[index].dbfs * Double(frames)
                measurement.counted += frames
            }
            if Double(measurement.counted) >= Self.measureSeconds * Double(sampleRate) {
                finish(id, level: measurement.sum / Double(measurement.counted))
            } else {
                measurements[id] = measurement
            }
        }
    }

    /// A USB Channel's level in dBFS, once enough audio has come in; nil when the audio stopped first, or the Task
    /// was canceled.
    public func measure(usbChannel: Int) async -> Double? {
        let id = nextID
        nextID += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                measurements[id] = Measurement(usbChannel: usbChannel, continuation: continuation)
            }
        } onCancel: {
            // Runs after the measurement is in place, even when the Task was already canceled: this waits its turn.
            Task { @MainActor in self.finish(id, level: nil) }
        }
    }

    /// Whether a measurement on `usbChannel` is under way, for tests to feed windows only once it is.
    func isMeasuring(usbChannel: Int) -> Bool {
        measurements.values.contains { $0.usbChannel == usbChannel }
    }

    private func finish(_ id: Int, level: Double?) {
        measurements.removeValue(forKey: id)?.continuation.resume(returning: level)
    }
}

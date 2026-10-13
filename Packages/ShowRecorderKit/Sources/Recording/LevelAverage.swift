/// How auto-gain measures a USB Channel's level (#554): half a second for the meter to follow a gain move, then
/// 20 readings of its Average 100 ms apart, about 2 s, averaged. -120 when the channel has no reading.
@MainActor
public enum LevelAverage {
    /// `reading` gives the channel's Average now, in dBFS, or nil when it isn't metered.
    public static func measure(
        reading: () -> Double?, sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Double {
        await sleep(.milliseconds(500))
        var readings: [Double] = []
        for _ in 0..<20 {
            if let level = reading() { readings.append(level) }
            await sleep(.milliseconds(100))
        }
        return readings.isEmpty ? -120 : readings.reduce(0, +) / Double(readings.count)
    }
}

import Foundation

/// Each channel's peak and average level over a Take, built from the windows the meter reads (about 30 a
/// second), so it needs no extra pass over the audio.
///
/// The average is the power average of the VU levels, weighted by frames: the square root of the mean of
/// the squares of each window's level (its average rectified level times the VU form factor). That is an
/// RMS-style figure, in dBFS, the same scale the meter shows.
struct TakeLevels {
    struct Summary: Equatable {
        var peakDbfs: Double
        var averageDbfs: Double
    }

    private var peaks: [Float]
    private var powerSums: [Double]
    private var frames: [Int]

    init(channelCount: Int) {
        peaks = Array(repeating: 0, count: channelCount)
        powerSums = Array(repeating: 0, count: channelCount)
        frames = Array(repeating: 0, count: channelCount)
    }

    mutating func add(_ windows: [ChannelLevel]) {
        for (channel, window) in windows.enumerated() where peaks.indices.contains(channel) {
            peaks[channel] = max(peaks[channel], window.peak)
            let level = Double(window.meanRectified) * VUMeter.formFactor
            powerSums[channel] += level * level * Double(window.frames)
            frames[channel] += window.frames
        }
    }

    var summary: [Summary] {
        peaks.indices.map { channel in
            let average = frames[channel] > 0 ? (powerSums[channel] / Double(frames[channel])).squareRoot() : 0
            return Summary(peakDbfs: Self.dbfs(Double(peaks[channel])), averageDbfs: Self.dbfs(average))
        }
    }

    private static func dbfs(_ linear: Double) -> Double {
        linear > 0 ? max(20 * log10(linear), VUMeter.floorDbfs) : VUMeter.floorDbfs
    }
}

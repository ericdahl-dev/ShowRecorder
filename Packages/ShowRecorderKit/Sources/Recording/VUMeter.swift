import Foundation

/// One channel's VU reading, from the average rectified level of each short window of audio.
///
/// Calibrated like a VU meter: 0 VU is the RMS of a steady sine, so the average of the rectified signal
/// is scaled by pi / (2 sqrt 2), about 1.11. The needle's ballistics are a second-order system that reaches
/// 99% of a steady level in 300 ms with about 1% overshoot (damping 0.826, natural frequency 13.969 rad/s),
/// and falls the same way.
///
/// The system is advanced exactly over each window, treating the level as constant across it, so the
/// reading doesn't depend on how the audio was cut into windows.
public struct VUMeter: Sendable {
    /// What a silent channel reads, in dBFS.
    public static let floorDbfs = -80.0

    /// The ratio of a sine's RMS to its average rectified level.
    static let formFactor = Double.pi / (2 * 2.0.squareRoot())

    /// Damping ratio (1% overshoot) and natural frequency (99% in 300 ms) of the needle.
    private static let damping = 0.826
    private static let naturalFrequency = 13.969

    /// The needle's position as a linear level (1 is full scale RMS-equivalent), and its speed.
    public private(set) var level = 0.0
    private var velocity = 0.0

    public init() {}

    /// Advances the meter over a window of `seconds` in which the average rectified level (0...1 of full
    /// scale) was `meanRectified`, and returns the reading in dBFS.
    @discardableResult
    public mutating func update(meanRectified: Double, seconds: Double) -> Double {
        let target = meanRectified * Self.formFactor
        // Distance from the target and its rate; the free response of a damped oscillator.
        let sigma = Self.damping * Self.naturalFrequency
        let damped = Self.naturalFrequency * (1 - Self.damping * Self.damping).squareRoot()
        let e0 = level - target
        let v0 = velocity
        let decay = exp(-sigma * seconds)
        let (cosine, sine) = (cos(damped * seconds), sin(damped * seconds))
        let e = decay * (e0 * cosine + (v0 + sigma * e0) / damped * sine)
        velocity = decay * (v0 * cosine - (Self.naturalFrequency * Self.naturalFrequency * e0 + sigma * v0) / damped * sine)
        level = target + e
        // The needle can't go below zero, and stops there.
        if level < 0 {
            level = 0
            velocity = max(velocity, 0)
        }
        return dbfs
    }

    /// The current reading in dBFS, never below the floor.
    public var dbfs: Double { level > 0 ? max(20 * log10(level), Self.floorDbfs) : Self.floorDbfs }
}

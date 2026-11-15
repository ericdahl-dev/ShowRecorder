import Foundation

/// How loud each channel of the Demo signal is (Debug and TestFlight builds, screenshots and Page videos): a level
/// that drifts slowly per channel, its average mostly in the meters' green target band and its peaks never red, so
/// it looks like a well-set show (Eric, 2026-11-15). The last channel stays silent, to show an unused USB Channel.
public enum DemoSignalLevel {
    /// The peak level, linear 0...1, of `channel` (0-based) of `count` at this `phase`. The signal is uniform noise of
    /// this peak, so its average is `peak / √3`.
    public static func peak(channel: Int, of count: Int, phase: Double) -> Float {
        guard channel != count - 1 else { return 0 }
        return Float(0.25 + 0.05 * sin(phase + Double(channel) * 0.6))
    }
}

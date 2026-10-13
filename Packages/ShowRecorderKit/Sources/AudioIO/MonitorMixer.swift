import Foundation

/// Fills the headphone monitor's output (#233): the ring's audio in both ears, plus a test tone when asked, but only
/// while the monitor is on and the output is headphones. Otherwise silence, and the ring is drained. Lives on the output
/// callback's thread; real-time safe (ADR 0002).
public struct MonitorMixer: Sendable {
    /// What the output callback reads from atomics before each render.
    public struct Flags: Equatable, Sendable {
        public var monitor: Bool
        public var tone: Bool
        public var headphones: Bool

        public init(monitor: Bool, tone: Bool, headphones: Bool) {
            self.monitor = monitor
            self.tone = tone
            self.headphones = headphones
        }
    }

    /// The test tone: 1 kHz at -18 dBFS.
    public static let toneHz = 1_000.0
    public static let toneLevel = Float(pow(10, -18.0 / 20))

    /// At most this many frames wait in the ring after a render; older ones are skipped, so the delay stays bounded.
    public var latencyLimit: Int
    private let step: Double
    private var phase = 0.0

    public init(sampleRate: Double, latencyLimit: Int = 4_096) {
        step = 2 * Double.pi * Self.toneHz / max(sampleRate, 1)
        self.latencyLimit = latencyLimit
    }

    public mutating func render(
        left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int, ring: MonitorRing, flags: Flags
    ) {
        guard flags.monitor, flags.headphones else {
            ring.drain()
            left.update(repeating: 0, count: count)
            right.update(repeating: 0, count: count)
            return
        }
        ring.read(into: left, count: count, latencyLimit: latencyLimit)
        if flags.tone {
            for frame in 0..<count {
                left[frame] += Self.toneLevel * Float(sin(phase))
                phase += step
                if phase >= 2 * Double.pi { phase -= 2 * Double.pi }
            }
        }
        right.update(from: left, count: count)
    }
}

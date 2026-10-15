import Foundation
@testable import AudioIO
import Testing

/// What the headphone monitor plays (#233): the ring's audio and a test tone, only when it is on and the output is
/// headphones; otherwise silence, with the ring kept drained so turning it on doesn't play old audio.
@Suite("Monitor mixer")
struct MonitorMixerTests {
    func ring(_ samples: [Float]) -> MonitorRing {
        let ring = MonitorRing(capacity: 64)
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) }
        return ring
    }

    func render(_ mixer: inout MonitorMixer, _ ring: MonitorRing, count: Int, flags: MonitorMixer.Flags) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: -1, count: count), right = [Float](repeating: -1, count: count)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                mixer.render(left: l.baseAddress!, right: r.baseAddress!, count: count, ring: ring, flags: flags)
            }
        }
        return (left, right)
    }

    @Test("Off, or not on headphones: silence, and the ring is drained")
    func silentWhenOffOrNotHeadphones() {
        var mixer = MonitorMixer(sampleRate: 48_000)
        for flags in [MonitorMixer.Flags(monitor: false, tone: true, headphones: true),
                      MonitorMixer.Flags(monitor: true, tone: true, headphones: false)] {
            let ring = ring([0.5, 0.5, 0.5, 0.5])
            let out = render(&mixer, ring, count: 4, flags: flags)
            #expect(out.left == [0, 0, 0, 0] && out.right == [0, 0, 0, 0])
            #expect(ring.availableFrames == 0)
        }
    }

    @Test("On headphones, the ring's audio plays in both ears")
    func playsTheRing() {
        var mixer = MonitorMixer(sampleRate: 48_000)
        let out = render(&mixer, ring([0.1, 0.2, 0.3]), count: 3, flags: .init(monitor: true, tone: false, headphones: true))
        #expect(out.left == [0.1, 0.2, 0.3] && out.right == [0.1, 0.2, 0.3])
    }

    @Test("The test tone is a 1 kHz sine at -18 dBFS, continuous from one call to the next, added to the ring's audio")
    func toneIsContinuous() {
        var mixer = MonitorMixer(sampleRate: 48_000)
        let flags = MonitorMixer.Flags(monitor: true, tone: true, headphones: true)
        let first = render(&mixer, ring([]), count: 30, flags: flags).left
        let second = render(&mixer, ring([0.25]), count: 18, flags: flags).left
        let amplitude = Float(pow(10, -18.0 / 20))
        let expected = (0..<48).map { amplitude * Float(sin(2 * Double.pi * 1_000 * Double($0) / 48_000)) }
        for (index, sample) in (first + second).enumerated() {
            let ringSample: Float = index == 30 ? 0.25 : 0
            #expect(abs(sample - (expected[index] + ringSample)) < 1e-5, "frame \(index)")
        }
    }
}

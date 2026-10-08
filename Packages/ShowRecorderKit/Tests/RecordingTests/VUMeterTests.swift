import Foundation
@testable import Recording
import Testing

/// The VU reading of a channel from the average rectified level of each short window.
@Suite("VU meter")
struct VUMeterTests {
    /// The average rectified level of a sine at `dbfs` RMS: 2/pi of its peak.
    static func meanRectified(sineAtRMS dbfs: Double) -> Double {
        let peak = pow(10, dbfs / 20) * 2.0.squareRoot()
        return 2 * peak / .pi
    }

    /// Feeds a constant level for `seconds` in windows of `window` seconds; returns the last reading in dBFS.
    static func settle(_ meter: inout VUMeter, level: Double, seconds: Double, window: Double = 1.0 / 30) -> Double {
        var reading = 0.0
        for _ in 0..<Int((seconds / window).rounded()) { reading = meter.update(meanRectified: level, seconds: window) }
        return reading
    }

    @Test("A steady sine settles at its RMS level: 0 VU is the sine's RMS, whatever the level")
    func sineReadsItsRMS() {
        for dbfs in [-6.0, -18.0, -30.0] {
            var meter = VUMeter()
            let reading = Self.settle(&meter, level: Self.meanRectified(sineAtRMS: dbfs), seconds: 3)
            #expect(abs(reading - dbfs) < 0.1, "\(dbfs) dBFS read as \(reading)")
        }
    }

    @Test("From silence, the reading reaches 99% of the level in about 300 ms and overshoots by about 1%")
    func stepResponse() {
        for window in [1.0 / 60, 1.0 / 30, 0.01] {
            var meter = VUMeter()
            let input = 0.5 / VUMeter.formFactor  // reads 0.5 linear when settled
            var time = 0.0
            var reached: Double?
            var peak = 0.0
            while time < 1.5 {
                _ = meter.update(meanRectified: input, seconds: window)
                time += window
                if reached == nil, meter.level >= 0.99 * 0.5 { reached = time }
                peak = max(peak, meter.level)
            }
            #expect(abs((reached ?? 9) - 0.3) <= window + 0.001, "window \(window): reached 99% at \(reached ?? -1) s")
            #expect(peak / 0.5 - 1 > 0.005 && peak / 0.5 - 1 < 0.012, "window \(window): overshoot \(peak / 0.5 - 1)")
        }
    }

    @Test("When the signal stops the reading falls back over the same 300 ms, and never goes below the floor")
    func fall() {
        var meter = VUMeter()
        let input = 0.5 / VUMeter.formFactor
        _ = Self.settle(&meter, level: input, seconds: 3)
        let window = 1.0 / 60
        var time = 0.0
        var fell: Double?
        while time < 1.5 {
            _ = meter.update(meanRectified: 0, seconds: window)
            time += window
            #expect(meter.level >= 0, "the needle doesn't go negative")
            if fell == nil, meter.level <= 0.01 * 0.5 { fell = time }
        }
        #expect(abs((fell ?? 9) - 0.3) <= 0.05, "fell to 1% at \(fell ?? -1) s")
        #expect(meter.dbfs == VUMeter.floorDbfs)
    }

    @Test("Silence reads the floor, never minus infinity or NaN")
    func silence() {
        var meter = VUMeter()
        #expect(meter.update(meanRectified: 0, seconds: 0.033) == VUMeter.floorDbfs)
        #expect(meter.update(meanRectified: 1e-12, seconds: 0.033) == VUMeter.floorDbfs)
        let loud = meter.update(meanRectified: 1, seconds: 0.5)
        #expect(loud.isFinite && loud <= 3.5, "full-scale rectified reads a little over 0 dBFS, as a VU would")
    }

    @Test("The reading doesn't depend on how the audio is cut into windows")
    func windowIndependence() {
        let input = Self.meanRectified(sineAtRMS: -12)
        var readings: [[Double]] = []
        for window in [0.010, 1.0 / 30, 0.050] {
            var meter = VUMeter()
            var atPoints: [Double] = []
            var time = 0.0
            for checkpoint in [0.15, 0.3, 1.0, 3.0] {
                while time + window / 2 < checkpoint { _ = meter.update(meanRectified: input, seconds: window); time += window }
                atPoints.append(meter.dbfs)
            }
            readings.append(atPoints)
        }
        // Checkpoints aren't hit exactly by every window length, but the settled ends and the shape agree.
        #expect(abs(readings[0][3] - readings[1][3]) < 0.05 && abs(readings[0][3] - readings[2][3]) < 0.05)
        #expect(abs(readings[0][2] - readings[1][2]) < 0.2 && abs(readings[0][2] - readings[2][2]) < 0.2)
    }
}

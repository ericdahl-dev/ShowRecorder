@testable import MixerLink
import Testing

/// The X32's value steps (#392), from Maillot's X32 OSC protocol 4.06, checked against X32-Edit on 2026-10-12.
@Suite("X32 values")
struct X32ValuesTests {
    @Test("A send level snaps to the nearest of its 161 steps, so X32-Edit's floor can't drop it a step",
          arguments: [(-14.8, -15.0), (-45.3, -45.0), (-72.4, -72.0), (3.1, 3.0), (-8.8, -8.75), (10.0, 10.0), (-90.0, -90.0)])
    func sendSnapsToNearestStep(written: Double, expected: Double) {
        #expect(X32Values.level.snap(written) == expected)
    }

    @Test("The float written for each of the 161 send steps floors back to that step, as the X32 reads it")
    func everySendStepSurvivesTheFloor() {
        for step in 0...160 {
            let db = X32Values.level.toDb(Double(step) / 160)
            let written = X32Values.level.oscFloat(db)
            #expect(Int((Double(written) * 160).rounded(.down)) == step, "step \(step) (\(db) dB) wrote \(written)")
        }
    }

    @Test("Gain, gate and compressor thresholds snap to 0.5 dB steps within their ranges")
    func linearScales() {
        #expect(X32Values.headampGain.snap(-6.3) == -6.5)
        #expect(X32Values.headampGain.snap(70) == 60, "clamped to +60")
        #expect(X32Values.gateThreshold.snap(-37.3) == -37.5)
        #expect(X32Values.compressorThreshold.snap(-25.2) == -25.0)
        #expect(X32Values.compressorThreshold.snap(-70) == -60, "clamped to -60")
        #expect(X32Values.headampGain.toDb(0) == -12 && X32Values.headampGain.toDb(1) == 60)
    }

    @Test("The fader has 1024 steps: -7.13 dB stays within a step (about 0.04 dB here) and round-trips")
    func fader() {
        let snapped = X32Values.fader.snap(-7.13)
        #expect(abs(snapped - -7.13) < 0.04)
        #expect(X32Values.fader.snap(snapped) == snapped)
        #expect(X32Values.fader.steps == 1023)
    }

    @Test("Every step of every scale survives the floor when written")
    func everyStepSurvives() {
        for scale in [X32Values.level, .fader, .headampGain, .gateThreshold, .compressorThreshold] {
            for step in 0...scale.steps {
                let written = scale.oscFloat(scale.toDb(Double(step) / Double(scale.steps)))
                #expect(Int((Double(written) * Double(scale.steps)).rounded(.down)) == step)
            }
        }
    }
}

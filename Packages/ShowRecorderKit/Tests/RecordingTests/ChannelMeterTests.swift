import Foundation
import Testing

@testable import Recording

/// What a channel's meter shows, decided apart from the view: where the average sits against the target
/// band, whether the peak is near clipping, and how the peak tick holds and falls.
@Suite("Channel meter")
struct ChannelMeterTests {
    @Test("The average is low below -18 dBFS, on target from -18 to -15, and hot above -15")
    func zones() {
        #expect(MeterZone(averageDbfs: -30) == .low)
        #expect(MeterZone(averageDbfs: -18.5) == .low)
        #expect(MeterZone(averageDbfs: -18) == .onTarget)
        #expect(MeterZone(averageDbfs: -16) == .onTarget)
        #expect(MeterZone(averageDbfs: -15) == .onTarget)
        #expect(MeterZone(averageDbfs: -14.5) == .hot)
        #expect(MeterZone(averageDbfs: -10) == .hot)
    }

    /// A window as the audio thread reports it, for a sine at `rmsDbfs` whose peaks reach `peakDbfs`.
    static func level(rmsDbfs: Double, peakDbfs: Double, frames: Int = 1600) -> ChannelLevel {
        let rms = pow(10, rmsDbfs / 20)
        return ChannelLevel(
            peak: Float(pow(10, peakDbfs / 20)), meanRectified: Float(rms / VUMeter.formFactor), frames: frames)
    }

    static func settled(rms: Double, peak: Double) -> ChannelMeter {
        var meter = ChannelMeter()
        for _ in 0..<90 { meter.update(level(rmsDbfs: rms, peakDbfs: peak), seconds: 1.0 / 30) }
        return meter
    }

    @Test("Average -16 with peaks at -4 is on target and the tick isn't red; -30 is low; -10 is hot; a peak at -2 is red")
    func readings() {
        let onTarget = Self.settled(rms: -16, peak: -4)
        #expect(onTarget.zone == .onTarget && !onTarget.peakIsHot)
        #expect(abs(onTarget.averageDbfs + 16) < 0.2)
        #expect(Self.settled(rms: -30, peak: -14).zone == .low)
        #expect(Self.settled(rms: -10, peak: -3.1).zone == .hot)
        #expect(!Self.settled(rms: -10, peak: -3.1).peakIsHot)
        #expect(Self.settled(rms: -16, peak: -2).peakIsHot)
        #expect(Self.settled(rms: -16, peak: 0).peakIsHot)
    }

    @Test("The peak tick holds for 1.5 s after the signal stops, then falls; a louder peak replaces it at once")
    func peakHold() {
        var meter = ChannelMeter()
        meter.update(Self.level(rmsDbfs: -16, peakDbfs: -4), seconds: 1.0 / 30)
        let silence = ChannelLevel(peak: 0, meanRectified: 0, frames: 1600)
        var time = 0.0
        while time < 1.4 { meter.update(silence, seconds: 1.0 / 30); time += 1.0 / 30 }
        #expect(abs(meter.peakDbfs + 4) < 0.01, "still holding at \(time) s: \(meter.peakDbfs)")
        while time < 2.5 { meter.update(silence, seconds: 1.0 / 30); time += 1.0 / 30 }
        #expect(meter.peakDbfs < -15, "falling after the hold: \(meter.peakDbfs)")
        while time < 6 { meter.update(silence, seconds: 1.0 / 30); time += 1.0 / 30 }
        #expect(meter.peakDbfs == VUMeter.floorDbfs, "fell to the floor, no lower")
        meter.update(Self.level(rmsDbfs: -20, peakDbfs: -10), seconds: 1.0 / 30)
        meter.update(Self.level(rmsDbfs: -20, peakDbfs: -6), seconds: 1.0 / 30)
        #expect(abs(meter.peakDbfs + 6) < 0.01)
        meter.update(Self.level(rmsDbfs: -20, peakDbfs: -12), seconds: 1.0 / 30)
        #expect(abs(meter.peakDbfs + 6) < 0.01, "a quieter window doesn't pull the held tick down")
    }

    @Test("The peak bar jumps to a new peak and falls back gently, 15% per 1/30 s, as the old meter did")
    func peakBar() {
        var meter = ChannelMeter()
        meter.update(Self.level(rmsDbfs: -20, peakDbfs: -4), seconds: 1.0 / 30)
        let peak = Float(pow(10, -4.0 / 20))
        #expect(abs(meter.peakBar - peak) < 1e-5)
        let silence = ChannelLevel(peak: 0, meanRectified: 0, frames: 1600)
        meter.update(silence, seconds: 1.0 / 30)
        #expect(abs(meter.peakBar - peak * 0.85) < 1e-5)
        meter.update(silence, seconds: 1.0 / 60)
        #expect(abs(meter.peakBar - peak * 0.85 * Float(pow(0.85, 0.5))) < 1e-5, "the fall follows real time, not the number of updates")
        meter.update(Self.level(rmsDbfs: -20, peakDbfs: -30), seconds: 1.0 / 30)
        #expect(meter.peakBar > Float(pow(10, -30.0 / 20)) * 2, "a quieter window doesn't snap the bar down")
        for _ in 0..<300 { meter.update(silence, seconds: 1.0 / 30) }
        #expect(meter.peakBar < 1e-4)
    }

    @Test("The peak bar is green up to -18 dBFS, yellow up to -6, red above, as the old meter was")
    func peakBarColors() {
        func color(_ dbfs: Double) -> PeakBarZone {
            var meter = ChannelMeter()
            meter.update(ChannelLevel(peak: Float(pow(10, dbfs / 20)), meanRectified: 0, frames: 1600), seconds: 1.0 / 30)
            return meter.peakBarZone
        }
        #expect(color(-40) == .green)
        #expect(color(-18.5) == .green)
        #expect(color(-17.5) == .yellow)
        #expect(color(-6.5) == .yellow)
        #expect(color(-5.5) == .red)
        #expect(color(0) == .red)
    }
}

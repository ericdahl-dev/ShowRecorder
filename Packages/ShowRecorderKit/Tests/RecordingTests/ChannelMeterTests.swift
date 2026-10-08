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
}

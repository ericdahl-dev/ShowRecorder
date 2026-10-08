import Foundation

/// Where a channel's average level sits against the target band, -18 to -15 dBFS.
///
/// The band is the usual recording level for live sound: it leaves 12 to 18 dB of headroom for peaks
/// (see CONTEXT.md, "Levels", and docs/adr/0005-level-meter-scale.md).
public enum MeterZone: Equatable, Sendable {
    case low, onTarget, hot

    public static let bandLowDbfs = -18.0
    public static let bandHighDbfs = -15.0

    public init(averageDbfs: Double) {
        if averageDbfs < Self.bandLowDbfs {
            self = .low
        } else if averageDbfs <= Self.bandHighDbfs {
            self = .onTarget
        } else {
            self = .hot
        }
    }
}

/// The color of the peak bar: the old meter's thresholds, on the peak.
public enum PeakBarZone: Equatable, Sendable {
    case green, yellow, red
}

/// One channel's meter as the screen draws it (the numbers are in docs/adr/0005-level-meter-scale.md): the VU average, and a peak tick that holds and then falls.
public struct ChannelMeter: Sendable {
    /// A peak above this reads as near clipping, and the tick turns red.
    public static let hotPeakDbfs = -3.0

    /// The tick holds this long after its peak, then falls at `fallDbfsPerSecond`.
    public static let holdSeconds = 1.5
    public static let fallDbfsPerSecond = 40.0

    private var vu = VUMeter()
    private var heldFor = 0.0
    /// The tick, in dBFS.
    public private(set) var peakDbfs = VUMeter.floorDbfs

    public init() {}

    /// The peak bar, linear 0...1: jumps to a peak and falls back 15% per 1/30 s, as the old meter did.
    public private(set) var peakBar: Float = 0

    public var peakBarZone: PeakBarZone {
        let dbfs = peakBar > 0 ? 20 * log10(Double(peakBar)) : VUMeter.floorDbfs
        return dbfs > -6 ? .red : dbfs > -18 ? .yellow : .green
    }

    public var averageDbfs: Double { vu.dbfs }
    public var zone: MeterZone { MeterZone(averageDbfs: averageDbfs) }
    public var peakIsHot: Bool { peakDbfs > Self.hotPeakDbfs }

    /// Takes the levels the audio thread gathered over the last `seconds`.
    public mutating func update(_ level: ChannelLevel, seconds: Double) {
        vu.update(meanRectified: Double(level.meanRectified), seconds: seconds)
        peakBar = max(level.peak, peakBar * Float(pow(0.85, seconds * 30)))
        let peak = level.peak > 0 ? max(20 * log10(Double(level.peak)), VUMeter.floorDbfs) : VUMeter.floorDbfs
        if peak >= peakDbfs {
            peakDbfs = peak
            heldFor = 0
        } else if heldFor < Self.holdSeconds {
            heldFor += seconds
        } else {
            peakDbfs = max(peakDbfs - Self.fallDbfsPerSecond * seconds, peak, VUMeter.floorDbfs)
        }
    }
}

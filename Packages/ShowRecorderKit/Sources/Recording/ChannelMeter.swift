import Foundation

/// Where a channel's average level sits against the target band, -18 to -15 dBFS.
///
/// The band is the usual recording level for live sound: it leaves 12 to 18 dB of headroom for peaks
/// (see CONTEXT.md).
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

/// One channel's meter as the screen draws it: the VU average, and a peak tick that holds and then falls.
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

    public var averageDbfs: Double { vu.dbfs }
    public var zone: MeterZone { MeterZone(averageDbfs: averageDbfs) }
    public var peakIsHot: Bool { peakDbfs > Self.hotPeakDbfs }

    /// Takes the levels the audio thread gathered over the last `seconds`.
    public mutating func update(_ level: ChannelLevel, seconds: Double) {
        vu.update(meanRectified: Double(level.meanRectified), seconds: seconds)
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

/// How wide each meter lane is, and the gap between lanes, so every USB Channel fits the record screen's width (#1174).
///
/// Only the width changes: the meters always keep their full height, in one row.
public struct MeterLaneLayout: Equatable, Sendable {
    /// One lane's width, in points: the meter, its clip mark and its label.
    public let laneWidth: Double
    /// The gap between two lanes, in points.
    public let spacing: Double
    /// How many lanes there are; the last one has the widest number.
    public let channelCount: Int

    /// The gap the meters have always had, kept while the lanes stay wide enough (18 channels on any iPhone).
    public static let roomySpacing = 4.0
    /// The gap when that would leave the lanes too narrow (32 channels on an iPhone).
    public static let tightSpacing = 2.0
    /// The widest a lane gets: wide enough that 18 channels fill an iPad, narrow enough that one or two channels aren't
    /// a screen-wide slab. A narrower row is centered.
    public static let widestLane = 64.0
    /// The narrowest lane that still gets the roomy gap.
    public static let narrowestRoomyLane = 12.0

    public init(channelCount: Int, availableWidth: Double) {
        self.channelCount = channelCount
        let roomy = Self.share(availableWidth, among: channelCount, gap: Self.roomySpacing)
        if roomy >= Self.narrowestRoomyLane {
            spacing = Self.roomySpacing
            laneWidth = min(roomy, Self.widestLane)
        } else {
            spacing = Self.tightSpacing
            laneWidth = Self.share(availableWidth, among: channelCount, gap: Self.tightSpacing)
        }
    }

    /// How wide one digit of a lane's number is, per point of font size: a little over SF's monospaced digits, so a number
    /// never runs into an ellipsis, and still under what lets "18" keep its full size in 18 lanes on the smallest iPhone.
    public static let digitWidthPerPoint = 0.68

    /// The size for every lane's USB Channel number: the full size when the widest number ("18", "32") fits a lane,
    /// else the size at which it does. One size for the whole row, so every label is the same height and every meter
    /// ends on the same line; shrunk one by one, 1-9 stayed full size and 10-32 didn't.
    public func labelPointSize(fullSize: Double) -> Double {
        let widestNumber = Double(String(max(channelCount, 1)).count) * Self.digitWidthPerPoint
        // Rounded down to a hundredth of a point, so the number is never a hair wider than its lane.
        return min(fullSize, (laneWidth / widestNumber * 100).rounded(.down) / 100)
    }

    /// Each lane's equal share of the width once the gaps between them are taken out.
    private static func share(_ width: Double, among channelCount: Int, gap: Double) -> Double {
        let count = Double(max(channelCount, 1))
        return max((width - gap * (count - 1)) / count, 0)
    }
}

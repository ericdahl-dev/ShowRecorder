/// How wide each meter lane is, and the gap between lanes, so every USB Channel fits the record screen's width (#1174).
///
/// Only the width changes: the meters always keep their full height, in one row.
public struct MeterLaneLayout: Equatable, Sendable {
    /// One lane's width, in points: the meter, its clip mark and its label.
    public let laneWidth: Double
    /// The gap between two lanes, in points.
    public let spacing: Double

    public init(channelCount: Int, availableWidth: Double) {
        laneWidth = 64
        spacing = 4
    }
}

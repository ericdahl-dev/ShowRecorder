import Recording
import Testing

/// The record screen's meter lanes (#1174): every USB Channel fits the width, in one row, so the meters keep their height.
@Suite("Meter lane layout")
struct MeterLaneLayoutTests {
    /// The narrowest iPhone the app runs on (iPhone SE, 375 pt) in portrait, less the screen's 16 pt padding each side.
    let smallestPortraitWidth = 343.0

    @Test("32 USB Channels fit the smallest iPhone's width in portrait")
    func thirtyTwoChannelsFitTheSmallestIPhone() {
        let layout = MeterLaneLayout(channelCount: 32, availableWidth: smallestPortraitWidth)
        let total = 32 * layout.laneWidth + 31 * layout.spacing
        #expect(total <= smallestPortraitWidth)
        #expect(layout.laneWidth >= 8, "a meter is never narrower than 8 pt")
    }

    @Test("18 USB Channels look as before: 4 pt gaps and an equal share of the width, on the smallest iPhone and an iPhone 17 Pro")
    func eighteenChannelsLookAsBefore() {
        for width in [smallestPortraitWidth, 370.0] {
            let layout = MeterLaneLayout(channelCount: 18, availableWidth: width)
            #expect(layout.spacing == 4, "\(width)")
            #expect(layout.laneWidth == (width - 17 * 4) / 18, "\(width)")
        }
    }
}

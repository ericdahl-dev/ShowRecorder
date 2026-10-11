@testable import Recording
import Testing

/// Where the Marker list, Channel names and Settings open, so Stop and Marker stay in reach during a Take.
@Suite("Live panel placement")
struct LivePanelPlacementTests {
    @Test("iPhone portrait opens the panel over the meters, so the transport below stays in reach")
    func portraitPhone() {
        #expect(LivePanelPlacement(horizontalCompact: true, verticalCompact: false) == .overMeters)
    }

    @Test("iPhone landscape, small or Max, opens the panel beside the meters")
    func landscapePhone() {
        #expect(LivePanelPlacement(horizontalCompact: true, verticalCompact: true) == .besideMeters)
        #expect(LivePanelPlacement(horizontalCompact: false, verticalCompact: true) == .besideMeters)
    }

    @Test("iPad and Mac keep the sheet until their docked panels (#255)")
    func regular() {
        #expect(LivePanelPlacement(horizontalCompact: false, verticalCompact: false) == .sheet)
    }
}

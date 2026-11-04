import Recording
import Testing

/// The landscape record screen's transport column (#1035): a full layout when it fits, a compact one when the text is
/// large or Display Zoom is on. Record and Marker never go away, and neither do Shows and Names.
@Suite("Landscape transport column")
struct TransportColumnLayoutTests {
    @Test("Every layout keeps Marker over the hint line over Record at the bottom, and the links to Shows and Names")
    func everyLayoutKeepsTheControls() {
        // Written out in the app's ViewThatFits in this order: the first that fits wins.
        #expect(TransportColumnLayout.allCases == [.full, .compact])
        for layout in TransportColumnLayout.allCases {
            #expect(Array(layout.parts.suffix(3)) == [.marker, .hint, .record], "\(layout)")
            #expect(layout.parts.contains(.links), "\(layout)")
            #expect(layout.parts.contains(.take), "\(layout)")
        }
    }

    @Test("The compact column gives the Show name to the top row's header; the full one keeps it in the column")
    func compactMovesTheShowNameToTheHeader() {
        #expect(TransportColumnLayout.full.parts.first == .showName)
        #expect(TransportColumnLayout.full.showNameInHeader == false)
        #expect(TransportColumnLayout.compact.parts.contains(.showName) == false)
        #expect(TransportColumnLayout.compact.showNameInHeader)
    }
}

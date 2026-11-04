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

    /// The text scales the app allows: default up to xxLarge (`.dynamicTypeSize(...xxLarge)`), about a third bigger.
    let textScales = [1.0, 1.1, 1.2, 1.25, 1.33]

    @Test("An iPhone 17 Pro at default text gets the full column; Display Zoom or xxLarge text gets the compact one")
    func budgetPicksByHeight() {
        // Landscape iPhone 17 Pro: 402 pt tall, the home indicator takes 21. With Display Zoom it is 375 pt tall.
        let pro = TransportColumnLayout.availableHeight(screenHeight: 402, bottomInset: 21)
        let zoomed = TransportColumnLayout.availableHeight(screenHeight: 375, bottomInset: 21)
        #expect(TransportColumnLayout.choose(availableHeight: pro, textScale: 1) == .full)
        #expect(TransportColumnLayout.choose(availableHeight: pro, textScale: 1.33) == .compact)
        #expect(TransportColumnLayout.choose(availableHeight: zoomed, textScale: 1) == .compact)
        #expect(TransportColumnLayout.choose(availableHeight: zoomed, textScale: 1.25) == .compact)
        // The user's phone (#1035): the compact column fits there even at the largest text the app allows.
        #expect(TransportColumnLayout.compact.height(textScale: 1.33) <= zoomed)
        // The smallest supported iPhone (SE, 375 pt tall in landscape, no home indicator) fits too.
        #expect(TransportColumnLayout.compact.height(textScale: 1.33) <= TransportColumnLayout.availableHeight(screenHeight: 375, bottomInset: 0))
    }

    @Test("The chosen column is never taller than the space whenever one fits, and the compact one is the shorter")
    func chosenColumnFits() {
        for scale in textScales {
            #expect(TransportColumnLayout.compact.height(textScale: scale) < TransportColumnLayout.full.height(textScale: scale), "\(scale)")
            for available in stride(from: 150.0, through: 600, by: 5) {
                let chosen = TransportColumnLayout.choose(availableHeight: available, textScale: scale)
                let anyFits = TransportColumnLayout.allCases.contains { $0.height(textScale: scale) <= available }
                if anyFits {
                    #expect(chosen.height(textScale: scale) <= available, "\(available) pt at \(scale)")
                } else {
                    // Nothing fits: the shortest one, as ViewThatFits takes its last choice.
                    #expect(chosen == .compact, "\(available) pt at \(scale)")
                }
            }
        }
    }
}

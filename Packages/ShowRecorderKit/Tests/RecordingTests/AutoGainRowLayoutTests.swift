import Recording
import Testing

/// A channel row in the Auto-gain sheet (#1149): the channel, its result and what moved to keep the mix, with Undo and
/// Auto-gain beside the text when there's room, under it when there isn't. Nothing runs past the row's edge.
@Suite("Auto-gain sheet row")
struct AutoGainRowLayoutTests {
    /// Portrait iPhone widths: an SE or a zoomed small phone, a zoomed iPhone 17 Pro, an iPhone 17 Pro, a Pro Max.
    let screenWidths = [320.0, 375.0, 402.0, 440.0]
    /// Default text up to the largest accessibility size (AX5 is about three times the default body).
    let textScales = [1.0, 1.1, 1.2, 1.35, 1.6, 2.0, 2.5, 3.1]

    @Test("The layouts, in the order the row tries them: buttons beside the text, under it in a row, then one per line")
    func order() {
        #expect(AutoGainRowLayout.allCases == [.beside, .buttonsBelow, .buttonsStacked])
    }

    @Test("An iPhone 17 Pro at default text keeps Undo and Auto-gain beside the text, as before")
    func defaultTextKeepsButtonsBeside() {
        let row = AutoGainRowLayout.rowWidth(screenWidth: 402)
        #expect(AutoGainRowLayout.choose(rowWidth: row, textScale: 1, showsUndo: true) == .beside)
        #expect(AutoGainRowLayout.choose(rowWidth: row, textScale: 1, showsUndo: false) == .beside)
    }

    @Test("The largest text the record screen allows (xxLarge) puts Undo and Auto-gain under the text")
    func largeTextMovesButtonsBelow() {
        let row = AutoGainRowLayout.rowWidth(screenWidth: 402)
        #expect(AutoGainRowLayout.choose(rowWidth: row, textScale: 1.35, showsUndo: true) == .buttonsBelow)
    }

    @Test("Accessibility text on a small phone puts each button on its own line")
    func accessibilityTextStacksButtons() {
        let row = AutoGainRowLayout.rowWidth(screenWidth: 320)
        #expect(AutoGainRowLayout.choose(rowWidth: row, textScale: 3.1, showsUndo: true) == .buttonsStacked)
    }

    @Test("At every width and text size, the chosen layout fits the row, and the text keeps room to wrap")
    func neverWiderThanTheRow() {
        for screen in screenWidths {
            let row = AutoGainRowLayout.rowWidth(screenWidth: screen)
            #expect(row < screen, "\(screen)")
            for scale in textScales {
                for showsUndo in [true, false] {
                    let layout = AutoGainRowLayout.choose(rowWidth: row, textScale: scale, showsUndo: showsUndo)
                    let needed = layout.width(textScale: scale, showsUndo: showsUndo)
                    // At AX5 on the smallest phone not even one button fits on a line: stacked, its title wraps.
                    let fits = AutoGainRowLayout.allCases.contains {
                        $0.width(textScale: scale, showsUndo: showsUndo) <= row
                    }
                    guard fits else {
                        #expect(layout == .buttonsStacked, "\(screen) pt, text \(scale)")
                        continue
                    }
                    #expect(needed <= row, "\(screen) pt, text \(scale), Undo \(showsUndo): \(layout) needs \(needed)")
                    if layout == .beside {
                        #expect(row - layout.buttonsWidth(textScale: scale, showsUndo: showsUndo)
                            >= AutoGainRowLayout.minimumTextWidth)
                    }
                }
            }
        }
    }

    @Test("A wider row never moves the buttons further down")
    func widerRowNeverStacksMore() {
        for scale in textScales {
            var last = AutoGainRowLayout.buttonsStacked
            for width in stride(from: 200.0, through: 800, by: 10) {
                let layout = AutoGainRowLayout.choose(rowWidth: width, textScale: scale, showsUndo: true)
                let order = AutoGainRowLayout.allCases
                #expect(order.firstIndex(of: layout)! <= order.firstIndex(of: last)!, "\(width) pt at \(scale)")
                last = layout
            }
        }
    }
}

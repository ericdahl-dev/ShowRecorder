/// A channel row in the Auto-gain sheet (#1149), in the order the app tries them: Undo and Auto-gain beside the text
/// when the text keeps room to wrap, under it in a row when not, and one per line when even that row is too wide
/// (accessibility text on a small phone). The text always wraps; nothing in the row is wider than the row.
public enum AutoGainRowLayout: CaseIterable, Sendable {
    case beside, buttonsBelow, buttonsStacked

    // MARK: Widths in points at default text. The app scales them by the body text's scale.

    /// The "Undo" and "Auto-gain" titles as borderless buttons, a little over their measured widths.
    static let undoWidth = 46.0
    static let autoGainWidth = 82.0
    /// Between Undo and Auto-gain, and between the text and the buttons.
    public static let spacing = 12.0
    /// The least the text keeps beside the buttons: about 20 characters of caption, so the result still reads.
    public static let minimumTextWidth = 140.0
    /// An inset grouped list's margin and a row's own padding, on each side, on the widest iPhone (the narrower ones
    /// use a little less, so this errs on the narrow side).
    static let listInsets = 2 * (20.0 + 20.0)

    /// The width a row's content has in a sheet `screenWidth` wide.
    public static func rowWidth(screenWidth: Double) -> Double {
        screenWidth - listInsets
    }

    /// The buttons as this layout places them: side by side, or the wider one alone when stacked.
    public func buttonsWidth(textScale: Double, showsUndo: Bool) -> Double {
        let autoGain = Self.autoGainWidth * textScale
        guard showsUndo else { return autoGain }
        switch self {
        case .beside, .buttonsBelow: return Self.undoWidth * textScale + Self.spacing + autoGain
        case .buttonsStacked: return autoGain
        }
    }

    /// How wide the row must be for this layout: the buttons, plus the text's minimum when they sit beside it.
    public func width(textScale: Double, showsUndo: Bool) -> Double {
        let buttons = buttonsWidth(textScale: textScale, showsUndo: showsUndo)
        return self == .beside ? Self.minimumTextWidth + Self.spacing + buttons : buttons
    }

    /// The first layout, in `allCases` order, that fits `rowWidth`; stacked when none does.
    public static func choose(rowWidth: Double, textScale: Double, showsUndo: Bool) -> AutoGainRowLayout {
        allCases.first { $0.width(textScale: textScale, showsUndo: showsUndo) <= rowWidth } ?? .buttonsStacked
    }
}

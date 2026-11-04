/// The landscape record screen's transport column (#1035), in the order the app tries them: the full column when it
/// fits the height left under the top row, else the compact one. Large text and Display Zoom make the full one too tall.
/// Record is never smaller and never moves: it is always last, at the bottom, with Marker and the hint line above it.
public enum TransportColumnLayout: CaseIterable, Sendable {
    case full, compact

    /// What the column stacks, top to bottom.
    public enum Part: Sendable {
        /// The Show's name, which opens the Show sheet.
        case showName
        /// Shows, Names and (when offered) Gain.
        case links
        /// The Take's title and how long it has run.
        case take
        case marker
        /// "Hold to stop" or the Drive's saving line, in the gap between Marker and Record.
        case hint
        case record
    }

    public var parts: [Part] {
        switch self {
        case .full: [.showName, .links, .take, .marker, .hint, .record]
        case .compact: [.links, .take, .marker, .hint, .record]
        }
    }

    /// The compact column has no Show name row: the top row's header shows "<Show> ▾ · <elapsed>" instead, and a tap
    /// on it opens the Show sheet the way the row does.
    public var showNameInHeader: Bool { !parts.contains(.showName) }

    // MARK: The height budget, in points at default text. The app lays the column out with these numbers.

    /// The top row (header, status strip, Markers, gear): one 44 pt row, pinned, so it never leaves the screen.
    public static let topRowHeight = 44.0
    /// Above the top row and below the column.
    public static let screenPadding = 3.0
    /// Between the top row and the meters and column.
    public static let rowSpacing = 8.0
    /// Between the column's blocks: the Show and Take block, the spacer, Marker, the hint line and Record.
    public static let spacing = 8.0
    /// The Show name row and the links row: each a 44 pt tap target.
    public static let rowHeight = 44.0
    /// Below the links row, so the Take's title doesn't sit on the buttons.
    public static let linksGap = 6.0
    /// The least the spacer above Marker keeps; the note uses what the spacer has beyond it.
    public static let spacerMinimum = 4.0
    /// The hint line between Marker and Record.
    public static let hintHeight = 20.0
    /// Record never shrinks, in either layout.
    public static let recordSize = 64.0
    /// A line of caption text, and the Take's title3 line, at default text.
    static let captionLine = 16.0
    static let titleLine = 25.0
    /// Between Marker's circle and its "N Markers" label (`MarkerButtonLabel`).
    static let markerLabelGap = 4.0

    /// Marker's circle: a little smaller in the compact column, never smaller than 44 pt.
    public var markerSize: Double {
        switch self {
        case .full: 64
        case .compact: 56
        }
    }

    /// The column's width: room for each link at 44 pt, 8 pt apart. Gain, when offered, is a third link.
    public static func width(offersGain: Bool) -> Double {
        offersGain ? 148 : 128
    }

    /// The height the column under the top row has: the screen less the home indicator, the padding, the top row
    /// and the gap below it.
    public static func availableHeight(screenHeight: Double, bottomInset: Double) -> Double {
        screenHeight - bottomInset - 2 * screenPadding - topRowHeight - rowSpacing
    }

    /// How tall this layout's column is at `textScale` (1 at default text), without the note: the note only takes
    /// what the spacer has to spare, so a note coming or going never switches the layout during a Take.
    public func height(textScale: Double) -> Double {
        let blocks = parts.reduce(0.0) { total, part in
            switch part {
            case .showName: total + Self.rowHeight
            case .links: total + Self.rowHeight + Self.linksGap
            case .take: total + Self.titleLine * textScale
            case .marker: total + markerSize + (self == .full ? Self.markerLabelGap + Self.captionLine * textScale : 0)
            case .hint: total + Self.hintHeight
            case .record: total + Self.recordSize
            }
        }
        // The Show and Take block, the spacer, Marker, the hint line and Record, with a gap between each.
        return blocks + Self.spacerMinimum + 4 * Self.spacing
    }

    /// The first layout, in `allCases` order, whose column fits `availableHeight`; the compact one when none does.
    /// The app's ViewThatFits makes the same choice from the views' measured heights.
    public static func choose(availableHeight: Double, textScale: Double) -> TransportColumnLayout {
        allCases.first { $0.height(textScale: textScale) <= availableHeight } ?? .compact
    }
}

/// The links under the Show name on the record screen, in both orientations (#1035): each a symbol over its word in a
/// tinted, bordered button, so "Shows" and "Names" read as two buttons.
public enum TransportLink: CaseIterable, Sendable {
    case shows, names, gain

    /// Each at least 44 by 44 pt to hit.
    public static let minimumSize = 44.0
    public static let spacing = 8.0

    /// Shows, Names, then Gain when the Mixer offers auto-gain.
    public static func row(offersGain: Bool) -> [TransportLink] {
        offersGain ? [.shows, .names, .gain] : [.shows, .names]
    }

    /// The word under the symbol, and the VoiceOver label.
    public var word: String {
        switch self {
        case .shows: "Shows"
        case .names: "Names"
        case .gain: "Gain"
        }
    }

    /// The SF Symbol over the word.
    public var symbol: String {
        switch self {
        case .shows: "folder"
        case .names: "tag"
        case .gain: "slider.vertical.3"
        }
    }
}

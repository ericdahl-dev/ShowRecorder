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
}

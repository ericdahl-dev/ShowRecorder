import Destinations

/// The line about how the last Take's Copies ended up. "Complete" only speaks for Gaps, so the line also
/// says when there was a single Copy and how many Dropouts (audio neither Copy has) the Take had.
public struct CopySummary: Equatable, Sendable {
    public let text: String
    public let isProblem: Bool

    /// How each Copy of the last Take ended (#550); a Copy with no ended state (it never started) isn't counted.
    public init(copies: TakeCopies, dropoutCount: Int) {
        self.init(outcomes: Dictionary(uniqueKeysWithValues: DestinationKind.allCases.compactMap { kind in
            copies[kind].outcome.map { (kind, $0) }
        }), dropoutCount: dropoutCount)
    }

    /// Today's call with the last Take's outcomes, until the record screen reads `TakeCopies` itself (#550).
    public init(outcomes: [DestinationKind: CopyOutcome], dropoutCount: Int) {
        var parts = DestinationKind.allCases.compactMap { kind in
            outcomes[kind].map { "\(kind.name) copy: \($0.word)" }
        }
        if outcomes.count == 1 {
            parts[0] += outcomes[.device] == nil ? " (no device copy)" : " (no Drive)"
        }
        if dropoutCount > 0 { parts.append("\(dropoutCount) Dropout\(dropoutCount == 1 ? "" : "s")") }
        text = parts.joined(separator: " · ")
        isProblem = dropoutCount > 0 || outcomes.values.contains { $0 == .hasGaps || $0 == .repairFailed }
    }
}

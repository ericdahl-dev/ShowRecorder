import Destinations

/// The line about how the last Take's Copies ended up. "Complete" only speaks for Gaps, so the line also
/// says when there was a single Copy and how many Dropouts (audio neither Copy has) the Take had.
public struct CopySummary: Equatable, Sendable {
    public let text: String
    public let isProblem: Bool

    public init(outcomes: [DestinationKind: CopyOutcome], dropoutCount: Int) {
        func word(_ outcome: CopyOutcome) -> String {
            switch outcome {
            case .complete: "complete"
            case .hasGaps: "has Gaps"
            case .repaired: "Repaired"
            case .repairFailed: "Repair failed"
            }
        }
        var parts = [(DestinationKind.device, "Device"), (.drive, "Drive")].compactMap { kind, name in
            outcomes[kind].map { "\(name) copy: \(word($0))" }
        }
        if outcomes.count == 1 {
            parts[0] += outcomes[.device] == nil ? " (no device copy)" : " (no Drive)"
        }
        if dropoutCount > 0 { parts.append("\(dropoutCount) Dropout\(dropoutCount == 1 ? "" : "s")") }
        text = parts.joined(separator: " · ")
        isProblem = dropoutCount > 0 || outcomes.values.contains { $0 == .hasGaps || $0 == .repairFailed }
    }
}

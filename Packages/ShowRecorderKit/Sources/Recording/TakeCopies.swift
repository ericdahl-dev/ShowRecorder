import Destinations
import TakeFile

/// One Copy of a Take, as the screens read it (#550).
public enum CopyState: Equatable, Sendable {
    // While the Take runs.
    case recording
    /// Its Destination failed or ran short of space mid-Take; the Take carries on in the other Copy.
    case interrupted
    /// It never started: no Destination.
    case missing
    // Once the Take has ended.
    case complete
    /// Its Gaps are still silence: Repair couldn't fill them (the Copy ran short of space, say).
    case hasGaps
    /// Repair filled its Gaps from the other Copy.
    case repaired
    /// Repair tried and failed.
    case repairFailed
}

/// Copies of a Take (#550): what each Destination's Copy of one Take is doing, or ended as, keyed by Destination.
/// The one answer every screen reads; its Gaps come from Copy coverage.
public struct TakeCopies: Equatable, Sendable {
    public let isRunning: Bool
    /// Every Destination has a state, so two snapshots that read the same are equal.
    private let states: [DestinationKind: CopyState]

    init(isRunning: Bool, state: (DestinationKind) -> CopyState) {
        self.isRunning = isRunning
        states = Dictionary(uniqueKeysWithValues: DestinationKind.allCases.map { ($0, state($0)) })
    }

    /// Before any Take: none running, and every Copy missing.
    public static let none = TakeCopies(isRunning: false) { _ in .missing }

    public subscript(_ kind: DestinationKind) -> CopyState { states[kind] ?? .missing }

    /// The Copies that stopped mid-Take, while it runs; none once it has ended.
    public var stopped: Set<DestinationKind> {
        guard isRunning else { return [] }
        return Set(DestinationKind.allCases.filter { states[$0] == .interrupted })
    }
}

extension CopyState {
    /// How the Copy ended, once the Take has; nil while it runs or for a Copy that never started.
    var outcome: CopyOutcome? {
        switch self {
        case .complete: .complete
        case .hasGaps: .hasGaps
        case .repaired: .repaired
        case .repairFailed: .repairFailed
        case .recording, .interrupted, .missing: nil
        }
    }
}

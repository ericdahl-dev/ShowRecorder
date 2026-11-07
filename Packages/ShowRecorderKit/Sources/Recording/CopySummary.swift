import Destinations

/// The line about how the last Take's Copies ended up. "Complete" only speaks for Gaps, so the line also
/// says when there was a single Copy and how many Dropouts (audio neither Copy has) the Take had.
public struct CopySummary: Equatable, Sendable {
    public let text: String
    public let isProblem: Bool

    /// The summary of the last Take, or nil while a Take runs or when no Copy of it ended (there was no Take).
    /// - Parameter deviceWord: the device the app runs on (iPhone, iPad or Mac), for a Drive only Take's line and a missed Drive's.
    /// - Parameter driveCopyAllowed: false on Free, which has no Drive Copy: then a Take without one missed nothing.
    public static func ofLastTake(
        _ copies: TakeCopies, dropoutCount: Int, deviceWord: String = "iPhone", driveCopyAllowed: Bool = true
    ) -> CopySummary? {
        guard !copies.isRunning, DestinationKind.allCases.contains(where: { copies[$0].outcome != nil }) else { return nil }
        return CopySummary(copies: copies, dropoutCount: dropoutCount, deviceWord: deviceWord, driveCopyAllowed: driveCopyAllowed)
    }

    /// How each Copy of the last Take ended (#550); a Copy with no ended state (it never started) isn't counted.
    /// A Drive only Take (#196, ADR 0006) speaks of the Drive alone: the Device only stood in. A Take recorded to the Device
    /// by choice (#805), or on Free, misses no Drive; any other Take on the Device alone missed it, and says so as a warning (#1151).
    public init(copies: TakeCopies, dropoutCount: Int, deviceWord: String = "iPhone", driveCopyAllowed: Bool = true) {
        let outcomes = Dictionary(uniqueKeysWithValues: DestinationKind.allCases.compactMap { kind in
            copies[kind].outcome.map { (kind, $0) }
        })
        guard copies.isDriveOnly else {
            if outcomes.count == 1, let device = outcomes[.device], !copies.isDeviceOnly, driveCopyAllowed {
                let gaps = device == .complete ? [] : ["Device copy: \(device.word)"]
                self.init(parts: ["Saved on this \(deviceWord) only: the Drive was missing"] + gaps, outcomes: outcomes,
                          dropoutCount: dropoutCount, missedDrive: true)
                return
            }
            self.init(outcomes: outcomes, dropoutCount: dropoutCount, isDeviceOnly: copies.isDeviceOnly)
            return
        }
        let onDevice = "On this \(deviceWord) until the Drive is back"
        let line = copies[.device] == .standInKept ? onDevice : outcomes[.drive].map { "Drive copy: \($0.word)" } ?? onDevice
        let moved = copies[.device] == .moved ? ["moved from this \(deviceWord)"] : []
        self.init(parts: [line] + moved, outcomes: outcomes, dropoutCount: dropoutCount)
    }

    /// Each ended Copy's line; a lone Copy says which one was missing, unless the Device was chosen.
    private init(outcomes: [DestinationKind: CopyOutcome], dropoutCount: Int, isDeviceOnly: Bool) {
        var parts = DestinationKind.allCases.compactMap { kind in
            outcomes[kind].map { "\(kind.name) copy: \($0.word)" }
        }
        if outcomes.count == 1, !(isDeviceOnly && outcomes[.device] != nil) {
            parts[0] += outcomes[.device] == nil ? " (no device copy)" : " (no Drive)"
        }
        self.init(parts: parts, outcomes: outcomes, dropoutCount: dropoutCount)
    }

    private init(parts: [String], outcomes: [DestinationKind: CopyOutcome], dropoutCount: Int, missedDrive: Bool = false) {
        var parts = parts
        if dropoutCount > 0 { parts.append("\(dropoutCount) Dropout\(dropoutCount == 1 ? "" : "s")") }
        text = parts.joined(separator: " · ")
        isProblem = missedDrive || dropoutCount > 0 || outcomes.values.contains { $0 == .hasGaps || $0 == .repairFailed }
    }
}

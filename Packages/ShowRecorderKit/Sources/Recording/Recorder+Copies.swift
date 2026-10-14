import Destinations
import TakeFile

extension Recorder {
    /// Copies of a Take (#550).
    public var copies: TakeCopies {
        // While a Take runs, its Copies' running states; after it, how each ended. Only a Copy with a folder has an
        // outcome, so any other stays missing. The last Take's outcomes are kept while the next runs, but a running
        // Take reads its own.
        if isRecording, let session { return session.takeCopies }
        return TakeCopies(isRunning: isRecording, isDriveOnly: lastTakeWasDriveOnly) { kind in
            if !isRecording, kind == .device, lastTakeStandInMoved { return .moved }
            if !isRecording, kind == .device, lastTakeStandInKept { return .standInKept }
            let ended = isRecording ? nil : lastTakeOutcomes[kind].map(CopyState.init)
            return ended ?? .missing
        }
    }
}

extension CopyState {
    /// How a Copy of the last Take ended.
    init(_ outcome: CopyOutcome) {
        switch outcome {
        case .complete: self = .complete
        case .hasGaps: self = .hasGaps
        case .repaired: self = .repaired
        case .repairFailed: self = .repairFailed
        }
    }
}

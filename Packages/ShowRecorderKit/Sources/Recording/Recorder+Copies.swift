import Destinations
import TakeFile

extension Recorder {
    /// Copies of a Take (#550), from what the Recorder says today about each Copy.
    public var copies: TakeCopies {
        // While a Take runs, its Copies' running words; after it, how each ended (a Copy that never started stays
        // missing). The last Take's outcomes are kept while the next runs, but a running Take reads its own.
        if isRecording, let session { return session.takeCopies }
        return TakeCopies(isRunning: isRecording, isDriveOnly: lastTakeWasDriveOnly) { kind in
            if !isRecording, kind == .device, lastTakeStandInMoved { return .moved }
            let ended = isRecording ? nil : lastTakeOutcomes[kind].map(CopyState.init)
            return ended ?? CopyState(copyStatus(kind))
        }
    }
}

extension CopyState {
    /// From today's running words, while the readers move over.
    init(_ status: CopyStatus) {
        switch status {
        case .recording: self = .recording
        case .interrupted: self = .interrupted
        case .missing: self = .missing
        }
    }
}

extension CopyState {
    /// From today's ended words, while the readers move over.
    init(_ outcome: CopyOutcome) {
        switch outcome {
        case .complete: self = .complete
        case .hasGaps: self = .hasGaps
        case .repaired: self = .repaired
        case .repairFailed: self = .repairFailed
        }
    }
}

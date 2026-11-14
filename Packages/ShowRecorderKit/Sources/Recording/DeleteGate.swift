/// Whether the delete sheet may delete a Show now. The open Show no longer has to be ended by hand first: with no
/// Take running, the sheet ends it and then deletes (#1216).
public enum DeleteGate: Equatable, Sendable {
    case ready
    case endShowFirst
    case blocked(String)

    /// `wholeShow` is false for deleting one Take or one file, which never ends the open Show.
    public static func decide(isRecording: Bool, isFinishing: Bool, isOpenShow: Bool, wholeShow: Bool) -> DeleteGate {
        if isRecording { return .blocked("A Take is running. Stop it first.") }
        if isFinishing { return .blocked(RecorderError.finishing.errorDescription ?? "") }
        guard isOpenShow else { return .ready }
        return wholeShow ? .endShowFirst : .blocked("This Show is open. End it first (tap the Show name on the record screen).")
    }
}

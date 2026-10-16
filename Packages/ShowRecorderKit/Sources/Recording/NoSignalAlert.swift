/// The warning for #778: the Take is recording silence. It sits in the input slot, so the meters never move, and there
/// is no "signal is back" banner; the warning just goes away.
public enum NoSignalAlert {
    public static func make(isSilent: Bool, isRecording: Bool) -> ScreenAlert? {
        guard isSilent, isRecording else { return nil }
        let seconds = Int(NoSignalDetector.defaultWaitSeconds)
        return ScreenAlert(
            id: "noSignal", priority: .input, tone: .warning,
            text: "No signal on any channel for \(seconds) seconds. Check the mixer's USB routing, the cable and any muted microphone. The Take is still recording.")
    }
}

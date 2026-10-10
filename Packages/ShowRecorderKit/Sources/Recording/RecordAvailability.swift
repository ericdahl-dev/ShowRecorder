/// Why Record is dimmed when the recorder isn't Armed, and what to offer: Arm again, or the system Settings.
public enum RecordAvailability {
    public struct Block: Equatable, Sendable {
        public var text: String
        public var action: ScreenAlert.Action?
    }

    public static func block(
        isArmed: Bool, isRecording: Bool, micDenied: Bool, armFailed: Bool, disarmedForIdle: Bool, hasInputs: Bool
    ) -> Block? {
        guard !isArmed, !isRecording else { return nil }
        if micDenied { return Block(text: "Microphone access is off. Allow it in Settings.", action: .openSystemSettings) }
        if armFailed { return Block(text: "The input didn't start.", action: .arm) }
        if disarmedForIdle { return Block(text: "Disarmed after 30 minutes idle.", action: .arm) }
        if !hasInputs { return Block(text: "No audio input. Plug in your interface.", action: nil) }
        return Block(text: "Choose an input in Settings.", action: nil)
    }
}

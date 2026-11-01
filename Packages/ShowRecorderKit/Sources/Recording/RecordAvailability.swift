/// Why Record is dimmed when the recorder isn't Ready, and what to offer: Get ready again, or the system Settings.
public enum RecordAvailability {
    public struct Block: Equatable, Sendable {
        public var text: String
        public var action: ScreenAlert.Action?
    }

    public static func block(
        isReady: Bool, isRecording: Bool, micDenied: Bool, getReadyFailed: Bool, stoodDownForIdle: Bool, hasInputs: Bool
    ) -> Block? {
        guard !isReady, !isRecording else { return nil }
        if micDenied { return Block(text: "Microphone access is off. Allow it in Settings.", action: .openSystemSettings) }
        if getReadyFailed { return Block(text: "The input didn't start.", action: .getReady) }
        if stoodDownForIdle { return Block(text: "Stood down after 30 minutes idle.", action: .getReady) }
        if !hasInputs { return Block(text: "No audio interface. Plug in the Mixer's USB cable.", action: nil) }
        return Block(text: "Choose the audio interface in Settings.", action: nil)
    }
}

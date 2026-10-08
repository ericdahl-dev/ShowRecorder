/// What to do with the recorder when the screen that shows it goes away or comes back.
///
/// Only an explicit stop and the app ending end a Take. A screen being torn down (iOS discarding a scene,
/// a window closing) never does, and a screen that comes back never Arms a recorder that is already
/// Armed, because Arming again stops the Take.
public enum RecorderLifecycle {
    public enum Action: Equatable, Sendable {
        case none, arm, disarm
    }

    /// What to do when the operator closes the window the recorder is shown in (the Mac).
    public enum WindowCloseAction: Equatable, Sendable {
        case close
        /// A Take is running: ask whether to stop it, and close only if the answer is stop.
        case askToStop
    }

    /// The operator asked to close the window (the close button or Command-W).
    public static func windowCloseRequested(isRecording: Bool) -> WindowCloseAction {
        isRecording ? .askToStop : .close
    }

    /// The screen went away.
    public static func screenDisappeared(isRecording: Bool) -> Action {
        isRecording ? .none : .disarm
    }

    /// The screen appeared, or came back. `isArmed` is true while recording too.
    public static func screenAppeared(isArmed: Bool) -> Action {
        isArmed ? .none : .arm
    }
}

/// Decides what the recorder does when the system interrupts or resets audio, or the app moves
/// between foreground and background, and what the operator is told.
///
/// The app feeds it platform events (audio session notifications, scene phase) and carries out the
/// returned action. Nothing here ends a Take: going to the background or locking the screen does
/// nothing, and an interruption only stops input until it can be restarted.
///
/// While input is stopped no audio reaches the Take. When it comes back, the stretch it missed is written as
/// silence with a Dropout (the recorder sees the jump in the input's host time, #317), so the Stems keep their length.
public struct InterruptionPolicy: Sendable, Equatable {
    /// Why the system interrupted audio.
    public enum Reason: Sendable, Equatable {
        /// Another app, a call or Siri took the audio session, or the system gave no reason.
        case other
        /// The built-in microphone was muted (an iPad's Smart Folio closed, for example).
        case builtInMicMuted
        /// The audio input was disconnected.
        case routeDisconnected

        /// From the raw value of `AVAudioSessionInterruptionReasonKey`: 2 is `builtInMicMuted` and 4 is
        /// `routeDisconnected` (AVAudioSessionTypes.h). Anything else, or no value, is `.other`.
        public init(sessionReason raw: UInt?) {
            switch raw {
            case 2: self = .builtInMicMuted
            case 4: self = .routeDisconnected
            default: self = .other
            }
        }
    }

    public enum Event: Sendable, Equatable {
        /// The audio session was interrupted and input has stopped. `reason` says why, when the system does.
        case interruptionBegan(reason: Reason)
        /// The interruption is over. `shouldResume` is the system's hint.
        case interruptionEnded(shouldResume: Bool)
        /// The system's media services were reset: every audio object must be rebuilt.
        case mediaServicesReset
        /// The app tried to restart (or replace) input and couldn't.
        case restartFailed(String)
        /// Input is running again on the same Take.
        case restarted
        /// Input was replaced after a reset, but the new device's format didn't match the Take, so
        /// the Take was stopped and finalized and the recorder Armed on the new device.
        case takeEndedByReset
        /// Moving the running Take to the new route (after an iOS route change) failed, so no audio reaches it.
        case moveFailed(String)
        case takeStarted
        case becameActive
        case movedToBackground
    }

    public enum Action: Sendable, Equatable {
        case none
        /// Restart input on the Armed device, keeping the Take.
        case restartInput
        /// Build a fresh device and move input to it, keeping the Take if its format matches.
        case replaceDevice
    }

    public struct Response: Sendable, Equatable {
        public let action: Action
        /// A line for the log, if this event is worth one.
        public let log: String?
    }

    /// True from an interruption or reset until input is running again.
    public private(set) var isInputStopped = false
    /// What the record screen's banner says, or nil for no banner.
    public private(set) var notice: String?
    /// The next restart has to build a new device rather than restart the old one.
    private var needsNewDevice = false
    /// Input is stopped because moving the Take to a new route failed, not because of an interruption, so
    /// the next route change should try the move again.
    private var moveFailed = false

    public init() {}

    public mutating func handle(_ event: Event, isRecording: Bool) -> Response {
        switch event {
        case .movedToBackground:
            return Response(action: .none, log: nil)

        case .becameActive:
            guard isInputStopped else { return Response(action: .none, log: nil) }
            return Response(action: restartAction, log: "App became active with input stopped; restarting input")

        case .interruptionBegan(let reason):
            isInputStopped = true
            let notice: String
            let detail: String
            switch reason {
            case .other:
                notice = isRecording
                    ? "Audio input was interrupted (a call, Siri or another app). The Take is still open, but nothing is recorded until input comes back."
                    : "Audio input was interrupted (a call, Siri or another app)."
                detail = ""
            case .builtInMicMuted:
                notice = isRecording
                    ? "The built-in microphone was muted (an iPad's Smart Folio closed, for example). The Take is still open, but nothing is recorded until input comes back."
                    : "The built-in microphone was muted (an iPad's Smart Folio closed, for example)."
                detail = " (built-in microphone muted)"
            case .routeDisconnected:
                notice = isRecording
                    ? "The audio input was disconnected. Check the connection. The Take is still open, but nothing is recorded until input comes back."
                    : "The audio input was disconnected. Check the connection."
                detail = " (input disconnected)"
            }
            self.notice = notice
            return Response(action: .none, log: "Audio session interruption began" + (isRecording ? " during a Take" : "") + detail)

        case .interruptionEnded(let shouldResume):
            guard isInputStopped else { return Response(action: .none, log: "Audio session interruption ended") }
            // During a Take, always try: losing the rest of the Show is worse than a refused restart.
            let action: Action = (shouldResume || isRecording) ? restartAction : .none
            let hint = shouldResume ? "should resume" : "should not resume"
            return Response(action: action, log: "Audio session interruption ended (\(hint))")

        case .mediaServicesReset:
            isInputStopped = true
            needsNewDevice = true
            notice = isRecording
                ? "The system reset its audio. Reconnecting input; nothing is recorded until it comes back."
                : "The system reset its audio. Reconnecting input."
            return Response(action: .replaceDevice, log: "Media services were reset" + (isRecording ? " during a Take" : ""))

        case .restartFailed(let reason):
            notice = "Couldn't restart audio input: \(reason). ShowRecorder tries again when it's back in the foreground."
            return Response(action: .none, log: "Restarting input failed: \(reason)")

        case .moveFailed(let reason):
            isInputStopped = true
            needsNewDevice = true
            moveFailed = true
            notice = "Couldn't move the Take to the new audio input: \(reason). The Take is still open, but nothing is recorded until input comes back. ShowRecorder tries again when the route changes or it's back in the foreground."
            return Response(action: .none, log: "Moving the Take to the new route failed: \(reason)")

        case .restarted:
            isInputStopped = false
            needsNewDevice = false
            moveFailed = false
            notice = isRecording
                ? "Input is back. Audio from the interruption is missing from this Take."
                : nil
            return Response(action: .none, log: "Input restarted" + (isRecording ? "; the Take continues" : ""))

        case .takeEndedByReset:
            isInputStopped = false
            needsNewDevice = false
            moveFailed = false
            notice = "The system reset its audio and the input changed, so the Take ended and was saved. Press record to start the next Take."
            return Response(action: .none, log: "Take ended after a media services reset: the new input's format differs")

        case .takeStarted:
            if !isInputStopped { notice = nil }
            return Response(action: .none, log: nil)
        }
    }

    private var restartAction: Action { needsNewDevice ? .replaceDevice : .restartInput }

    /// What to do when the iOS input route really changes.
    public enum RouteAction: Sendable, Equatable {
        /// Leave input alone; the interruption's restart picks up the new route.
        case none
        /// Arm on the new route (nothing to keep).
        case rearm
        /// Move input to the new route with `Recorder.restartInput(on:)`: the Take carries on if the
        /// format still matches, and is stopped and saved only if it doesn't.
        case moveInput
    }

    /// Decides what an iOS route change does. Calls and Siri can change the route as they begin and
    /// end; re-arming then would end the Take.
    public mutating func routeChanged(isRecording: Bool) -> RouteAction {
        if isInputStopped {
            // The old device describes the old route, so the restart must build a new one. After a failed
            // move there is no restart coming: try the move again on this route.
            needsNewDevice = true
            return moveFailed ? .moveInput : .none
        }
        return isRecording ? .moveInput : .rearm
    }
}

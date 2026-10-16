import Recording
import SwiftUI

/// The Stop button on the iPhone while a Take runs (#753): press and hold for a second, a red ring fills while held, and
/// letting go early does nothing but ask for the hint. It is the Watch's `HoldToStopButton` at the record button's size, so
/// the transport column keeps its height and nothing sits over the meters.
struct HoldToStopRecordButton: View {
    let size: CGFloat
    /// What VoiceOver reads, as on the tap button it replaces: "Stop <Take>".
    let label: String
    /// The hold finished, or VoiceOver's direct action.
    let stop: () -> Void
    /// A tap or an early release: the caller shows "Hold to stop".
    let hint: () -> Void
    @State private var gesture = HoldToStopGesture()

    var body: some View {
        RecordButtonLabel(isRecording: true, size: size)
            .overlay {
                Circle()
                    .trim(from: 0, to: gesture.isFilling ? 1 : 0)
                    .stroke(.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size - 4, height: size - 4)
                    // The fill is how long is left to hold, not decoration, so it runs even with Reduce Motion.
                    .animation(gesture.isFilling ? .linear(duration: HoldToStopGesture.holdSeconds) : .none, value: gesture.isFilling)
            }
            .onLongPressGesture(minimumDuration: HoldToStopGesture.holdSeconds) {
                gesture.holdCompleted()
                stop()
            } onPressingChanged: { pressing in
                if pressing {
                    gesture.pressBegan(at: .now)
                } else if gesture.pressEnded(at: .now) == .showHint {
                    hint()
                }
            }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Press and hold to stop the Take")
            .accessibilityAction { stop() }
    }
}

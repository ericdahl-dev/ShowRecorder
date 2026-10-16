import SwiftUI

/// The Stop button on the iPhone while a Take runs (#753): press and hold for a second, a red ring fills while held, and
/// letting go early does nothing but ask for the hint. It is the Watch's `HoldToStopButton` at the record button's size, so
/// the transport column keeps its height and nothing sits over the meters.
struct HoldToStopRecordButton: View {
    static let holdSeconds = 1.0
    let size: CGFloat
    /// What VoiceOver reads, as on the tap button it replaces: "Stop <Take>".
    let label: String
    /// The hold finished, or VoiceOver's direct action.
    let stop: () -> Void
    /// A tap or an early release: the caller shows "Hold to stop".
    let hint: () -> Void
    @State private var holding = false
    @State private var held = false
    @State private var pressStart = Date.distantPast

    var body: some View {
        RecordButtonLabel(isRecording: true, size: size)
            .overlay {
                Circle()
                    .trim(from: 0, to: holding ? 1 : 0)
                    .stroke(.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size - 4, height: size - 4)
                    // The fill is how long is left to hold, not decoration, so it runs even with Reduce Motion.
                    .animation(holding ? .linear(duration: Self.holdSeconds) : .none, value: holding)
            }
            .onLongPressGesture(minimumDuration: Self.holdSeconds) {
                held = true
                holding = false
                stop()
            } onPressingChanged: { pressing in
                if pressing {
                    held = false
                    pressStart = .now
                } else if !held, Date.now.timeIntervalSince(pressStart) < Self.holdSeconds * 0.9 {
                    // Judged by time as well as by `held`, so a finished hold never shows the hint whichever
                    // of the two callbacks SwiftUI sends first.
                    hint()
                }
                holding = pressing
            }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Press and hold to stop the Take")
            .accessibilityAction { stop() }
    }
}

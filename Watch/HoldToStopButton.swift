import SwiftUI

/// Stop on the wrist needs a press and hold (#100): a stray tap mid-song is the worst outcome. A ring fills over a
/// second while held; letting go early does nothing.
struct HoldToStopButton: View {
    static let holdSeconds = 1.0
    let action: () -> Void
    @State private var holding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.gray.opacity(0.4), lineWidth: 4)
            Circle()
                .trim(from: 0, to: holding ? 1 : 0)
                .stroke(.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // The fill is the feedback that it's working, so it shows even with Reduce Motion, as one step.
                .animation(holding ? .linear(duration: reduceMotion ? 0 : Self.holdSeconds) : .none, value: holding)
            Image(systemName: "stop.fill").font(.title3).foregroundStyle(.red)
        }
        .frame(width: 56, height: 56)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: Self.holdSeconds) {
            holding = false
            action()
        } onPressingChanged: { pressing in
            holding = pressing
        }
        .accessibilityLabel("Stop")
        .accessibilityHint("Press and hold to stop the Take")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

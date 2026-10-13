import SwiftUI
import WatchRemote

/// What the wrist shows: the recorder's state and elapsed time, a problem if there is one, and the commands. Marker
/// is the big button (the main reason to have the watch); Start is one tap; Stop needs a press and hold.
struct RemoteView: View {
    let model: WatchRemoteModel

    var body: some View {
        switch model.display {
        case .connecting:
            ProgressView("Connecting…")
        case .noLink:
            ContentUnavailableView("No link to iPhone", systemImage: "iphone.slash",
                                   description: Text("The recording on the iPhone carries on."))
        case .status(let status):
            // One screen, no scrolling: what's happening on top, the controls along the bottom.
            VStack(spacing: 6) {
                header(status.state)
                if let problem = status.problems.first {
                    Label(problem.text, systemImage: problem.symbol)
                        .font(.footnote)
                        .lineLimit(2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Problem: \(problem.text)")
                }
                if let note {
                    Text(note).font(.footnote).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
                controls(status.state)
            }
        }
    }

    @ViewBuilder
    private func header(_ state: WatchStatus.State) -> some View {
        switch state {
        case .notArmed:
            Text("Not Armed").font(.headline)
        case .armed:
            Text("Armed").font(.headline)
        case .recording(let startedAt, let takeTitle, let markerCount):
            VStack(spacing: 0) {
                Label("Recording", systemImage: "record.circle").font(.headline).foregroundStyle(.red)
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.title2.monospacedDigit())
                Text(markerCount == 1 ? "\(takeTitle) · 1 Marker" : "\(takeTitle) · \(markerCount) Markers")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    /// Marker is the big one (the main reason for the watch) and also the double tap; Stop beside it needs a hold,
    /// so the two can sit side by side.
    @ViewBuilder
    private func controls(_ state: WatchStatus.State) -> some View {
        switch state {
        case .recording:
            HStack(spacing: 8) {
                Button { model.send(.marker) } label: {
                    Label("Marker", systemImage: "bookmark.fill").frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .handGestureShortcut(.primaryAction)
                HoldToStopButton { model.send(.stop) }
            }
        case .armed:
            Button { model.send(.start) } label: {
                Label("Record", systemImage: "record.circle.fill").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        case .notArmed:
            Text(WatchRemoteModel.openPhoneText).font(.footnote).multilineTextAlignment(.center)
        }
    }

    /// The last command's outcome, while it's pending or when it didn't go through.
    private var note: String? {
        for kind in [WatchCommand.Kind.stop, .start, .marker] {
            switch model.commands[kind] {
            case .pending?: return "Sending…"
            case .failed(let reason)?: return reason
            case .unconfirmed?: return WatchRemoteModel.unconfirmedText
            default: continue
            }
        }
        return nil
    }
}

import ActivityKit
import SwiftUI
import TakeActivity
import WidgetKit

/// The widget extension: only the running Take's Live Activity (#136). Tapping it opens the app, which
/// shows the record screen.
@main
struct ShowRecorderWidgets: WidgetBundle {
    var body: some Widget {
        TakeLiveActivityWidget()
    }
}

struct TakeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TakeActivityAttributes.self) { context in
            TakeActivityView(take: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.takeTitle, systemImage: "record.circle.fill")
                        .labelStyle(RecordingLabelStyle())
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Elapsed(since: context.state.startedAt)
                        .font(.title3.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.showName).lineLimit(1)
                        Spacer()
                        Markers(count: context.state.markerCount)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
            } compactTrailing: {
                Elapsed(since: context.state.startedAt)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
            }
        }
        // The same Live Activity in the Apple Watch's Smart Stack (#100): recording status on the wrist at a glance.
        .supplementalActivityFamilies([.small])
    }
}

/// The Lock Screen banner, or on the Apple Watch's Smart Stack (the small family) a compact one.
private struct TakeActivityView: View {
    let take: TakeActivityContent
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            WatchStackView(take: take)
        default:
            LockScreenView(take: take)
                .padding()
        }
    }
}

/// The running Take on the watch's Smart Stack: recording, the elapsed time, and which Take.
private struct WatchStackView: View {
    let take: TakeActivityContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Recording", systemImage: "record.circle.fill")
                .labelStyle(RecordingLabelStyle())
                .font(.caption)
            Elapsed(since: take.startedAt, alignment: .leading)
                .font(.title3.weight(.semibold))
            Text(take.takeTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct LockScreenView: View {
    let take: TakeActivityContent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "record.circle.fill")
                .font(.title)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(take.takeTitle).font(.headline)
                Text(take.showName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Elapsed(since: take.startedAt).font(.title2.weight(.semibold))
                Markers(count: take.markerCount).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Counts up on its own, with no updates from the app.
private struct Elapsed: View {
    let since: Date
    /// The timer text fills the width it's given, so where its digits sit is set here, not outside.
    var alignment: TextAlignment = .trailing

    var body: some View {
        Text(timerInterval: since...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(alignment)
    }
}

private struct Markers: View {
    let count: Int

    var body: some View {
        Label(count == 1 ? "1 Marker" : "\(count) Markers", systemImage: "flag.fill")
    }
}

private struct RecordingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(.red)
            configuration.title
        }
    }
}

#Preview("Lock Screen", as: .content, using: TakeActivityAttributes()) {
    TakeLiveActivityWidget()
} contentStates: {
    TakeActivityContent(showName: "2026-10-12 Show", takeTitle: "Take 02", startedAt: .now.addingTimeInterval(-754), markerCount: 3)
}

#Preview("Dynamic Island expanded", as: .dynamicIsland(.expanded), using: TakeActivityAttributes()) {
    TakeLiveActivityWidget()
} contentStates: {
    TakeActivityContent(showName: "2026-10-12 Show", takeTitle: "Take 02", startedAt: .now.addingTimeInterval(-754), markerCount: 1)
}

#Preview("Dynamic Island compact", as: .dynamicIsland(.compact), using: TakeActivityAttributes()) {
    TakeLiveActivityWidget()
} contentStates: {
    TakeActivityContent(showName: "2026-10-12 Show", takeTitle: "Take 02", startedAt: .now.addingTimeInterval(-4_354), markerCount: 0)
}

#if os(iOS)
import ActivityKit
import TakeActivity

/// The running Take in the Dynamic Island and on the Lock Screen (#136). It only reads state the record
/// screen already has and never touches the audio path; if Live Activities are off it does nothing.
@MainActor
final class TakeLiveActivity {
    private var tracker = TakeActivityTracker()
    /// When a problem during the Take alerts (#545): once when new, quietly when it clears.
    private var alerts = ProblemAlertGate()
    /// The shown activity's id. `Activity` isn't Sendable, so tasks look it up by id rather than carry it.
    private var activityID: String?

    init() {
        // An activity left over from a run that ended without stopping its Take (the app was closed).
        Self.end(where: { _ in true })
    }

    /// `take` is the running Take, or nil when none is running.
    func follow(_ take: TakeActivityContent?) {
        switch tracker.next(take) {
        case .none:
            break
        case .start(let content):
            alerts.takeStarted()
            _ = alerts.alert(for: content.problems, at: .now)
            start(content)
        case .update(let content):
            guard let id = activityID else { return }
            // A new problem lights up the iPhone and buzzes the watch, even with neither app open (#545).
            let alert = alerts.alert(for: content.problems, at: .now).map {
                AlertConfiguration(title: "\($0.title)", body: "\($0.body)", sound: .default)
            }
            Task.detached {
                for activity in Activity<TakeActivityAttributes>.activities where activity.id == id {
                    await activity.update(ActivityContent(state: content, staleDate: nil), alertConfiguration: alert)
                }
            }
        case .replace(let content):
            end()
            alerts.takeStarted()
            _ = alerts.alert(for: content.problems, at: .now)
            start(content)
        case .end:
            end()
        }
    }

    private func start(_ content: TakeActivityContent) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activityID = try? Activity.request(attributes: TakeActivityAttributes(), content: ActivityContent(state: content, staleDate: nil)).id
    }

    private func end() {
        guard let id = activityID else { return }
        activityID = nil
        Self.end(where: { $0 == id })
    }

    private static func end(where matches: @escaping @Sendable (String) -> Bool) {
        Task.detached {
            for activity in Activity<TakeActivityAttributes>.activities where matches(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif

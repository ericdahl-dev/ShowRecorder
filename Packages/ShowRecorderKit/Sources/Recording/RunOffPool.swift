import Foundation

/// Runs `work` on its own thread and returns its result (#681). File work and hooks that can block belong here, not in a
/// `Task.detached`: a blocked task holds a cooperative pool thread, and with the pool small (a busy CI runner) the task
/// that would unblock it can never run.
func runOffPool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        let thread = Thread { continuation.resume(returning: work()) }
        thread.name = "ShowRecorder off-pool work"
        thread.qualityOfService = .userInitiated
        thread.start()
    }
}

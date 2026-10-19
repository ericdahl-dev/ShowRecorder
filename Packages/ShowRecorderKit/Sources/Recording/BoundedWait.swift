import Foundation

/// Waits for `task`, but no longer than `limit`: work that can hang on a Drive (a report write) must never hold up what
/// comes after it. The task itself is left running.
func waitBounded(_ task: Task<Void, Never>?, for limit: Duration) async {
    guard let task else { return }
    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
        func resume() {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume()
        }
    }
    await withCheckedContinuation { continuation in
        let once = Once(continuation)
        Task { await task.value; once.resume() }
        Task { try? await Task.sleep(for: limit); once.resume() }
    }
}

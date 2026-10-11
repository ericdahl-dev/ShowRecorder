import Synchronization

/// Counts how often a Drive's access was ended. The app may end it from any thread, so this counts safely.
final class ReleaseCounter: Sendable {
    private let value = Mutex(0)
    var count: Int { value.withLock { $0 } }
    func increment() { value.withLock { $0 += 1 } }
}

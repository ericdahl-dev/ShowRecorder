import Foundation

/// Where a Drive start job (on a thread of its own) and the Take waiting for it meet (#914). Whichever comes first
/// decides, once: the job's result, or the deadline. A job that finishes after the Take gave up is handed back, so it
/// discards what it made.
final class DriveStartHandoff: @unchecked Sendable {
    /// What the job came to.
    struct Finished: @unchecked Sendable {
        var prepared: TakeSession.PreparedDrive?
        /// The Drive was not there: nothing was asked of it.
        var noDrive: Bool
        /// Why, when the Drive says.
        var problem: String?
    }

    enum Outcome: @unchecked Sendable {
        case finished(Finished)
        case timedOut
    }

    private let lock = NSLock()
    private var outcome: Outcome?
    private var waiter: CheckedContinuation<Outcome, Never>?

    /// Waits for the job or the deadline, whichever comes first.
    func wait() async -> Outcome {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(returning: outcome)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    /// The job is done. Returns what it made when the deadline had already come, for the job to discard.
    func finish(_ finished: Finished) -> TakeSession.PreparedDrive? {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return finished.prepared
        }
        outcome = .finished(finished)
        let waiting = waiter
        waiter = nil
        lock.unlock()
        waiting?.resume(returning: .finished(finished))
        return nil
    }

    /// The deadline came. Ignored when the job finished first.
    func timeOut() {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        outcome = .timedOut
        let waiting = waiter
        waiter = nil
        lock.unlock()
        waiting?.resume(returning: .timedOut)
    }
}

/// Set by a Drive start job when the Drive was not there to be asked for.
final class DriveStartMissing: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

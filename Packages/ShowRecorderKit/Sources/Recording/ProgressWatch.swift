import Foundation

/// Whether a writer has made no progress for a window (#817): the test Stop uses to abandon a Copy that hung, and to wait for
/// one that is only slow. Time is given, not read, so it can be tested.
struct ProgressWatch {
    let window: Duration
    /// The longest gap between two looks that still counts as watching. A longer one means this thread was suspended (the
    /// app went to the background mid-save, #818), and the writer with it, so the gap isn't a stall.
    static let longestGap: Duration = .seconds(1)

    private var count: Int
    private var since: ContinuousClock.Instant
    private var lastLook: ContinuousClock.Instant

    init(window: Duration, count: Int, at now: ContinuousClock.Instant) {
        self.window = window
        self.count = count
        since = now
        lastLook = now
    }

    mutating func isStalled(count newCount: Int, at now: ContinuousClock.Instant) -> Bool {
        defer { lastLook = now }
        if newCount != count || now - lastLook > Self.longestGap {
            count = newCount
            since = now
            return false
        }
        return now - since >= window
    }
}

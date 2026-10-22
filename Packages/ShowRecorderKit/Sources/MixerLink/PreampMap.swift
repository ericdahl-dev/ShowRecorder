import Synchronization

/// Which preamp each input channel takes, as the driver last read it (#874), so a Mix Hold call, which clip protection
/// makes mid-Take, doesn't ask the Mixer for every channel each time. It is read ahead when the auto-gain sheet opens
/// and when a Take starts with clip protection on, and again when the Mixer pushes a routing change, when the channel
/// a move asks about no longer matches it, for a channel never read, and after the connection lapsed. A reconnect makes
/// a new driver, so a new map.
final class PreampMap: Sendable {
    struct Snapshot {
        /// A channel's preamp, `.some(nil)` when it has none; absent when not read yet or its read failed.
        var preamps: [Int: Int?]
        /// A routing change was pushed, or may have been missed, since the last complete read: what is held is a guess.
        var isStale: Bool
        /// Counts the changes, so a read can tell one landed while it was under way.
        var generation: Int
    }

    private let state = Mutex(Snapshot(preamps: [:], isStale: false, generation: 0))

    func snapshot() -> Snapshot { state.withLock { $0 } }

    /// The Mixer changed which input a channel takes, or the connection lapsed and pushes may have been missed.
    func invalidate() {
        state.withLock {
            $0.isStale = true
            $0.generation += 1
        }
    }

    /// Takes in what a read that began at `generation` got. A change landed meanwhile: what was read may be old, so none
    /// of it is kept and the map stays stale. A read that stopped early (`unread`) keeps a stale map stale and drops the
    /// channels it didn't reach, so they count as never read and are tried again.
    func store(_ read: [Int: Int?], unread: [Int], generation: Int) {
        state.withLock { map in
            guard map.generation == generation else { return }
            map.preamps.merge(read) { _, new in new }
            if unread.isEmpty {
                map.isStale = false
            } else if map.isStale {
                for channel in unread { map.preamps[channel] = nil }
            }
        }
    }
}

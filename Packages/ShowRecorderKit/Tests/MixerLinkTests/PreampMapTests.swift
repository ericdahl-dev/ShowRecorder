@testable import MixerLink
import Testing

/// The map of which preamp each channel takes (#874): a change pushed while a read is under way is not lost, and a
/// read that stops early doesn't make a stale map trusted.
@Suite("Preamp map")
struct PreampMapTests {
    @Test("A read that finishes with nothing pushed meanwhile is kept and makes the map current")
    func completeRead() {
        let map = PreampMap()
        map.invalidate()
        let generation = map.snapshot().generation

        map.store([1: 0, 2: 1], unread: [], generation: generation)

        #expect(map.snapshot().preamps == [1: 0, 2: 1])
        #expect(!map.snapshot().isStale)
    }

    @Test("A change pushed while a read is under way keeps the map stale and throws that read away")
    func pushDuringRead() {
        let map = PreampMap()
        let generation = map.snapshot().generation

        map.invalidate()
        map.store([1: 0, 2: 1], unread: [], generation: generation)

        #expect(map.snapshot().preamps.isEmpty)
        #expect(map.snapshot().isStale)
    }

    @Test("A read that stops early leaves a stale map stale and drops the channels it didn't reach")
    func partialReadOfAStaleMap() {
        let map = PreampMap()
        map.invalidate()
        map.store([1: 0, 2: 1, 3: 2], unread: [], generation: map.snapshot().generation)
        map.invalidate()   // a push: 1-3 are guesses now

        map.store([1: 0], unread: [2, 3], generation: map.snapshot().generation)

        #expect(map.snapshot().isStale)
        #expect(map.snapshot().preamps == [1: 0], "channels 2 and 3 count as never read")
    }

    @Test("A read that stops early on a current map keeps what was held for the channels it didn't reach")
    func partialReadOfACurrentMap() {
        let map = PreampMap()
        map.store([1: 0, 2: 1, 3: 2], unread: [], generation: 0)

        map.store([1: 0], unread: [2, 3], generation: 0)

        #expect(map.snapshot().preamps == [1: 0, 2: 1, 3: 2])
        #expect(!map.snapshot().isStale)
    }

    @Test("Two reads merge channel by channel, so a late one doesn't drop what the other found")
    func readsMerge() {
        let map = PreampMap()
        map.store([1: 0, 2: 1], unread: [3], generation: 0)
        map.store([3: 2], unread: [], generation: 0)

        #expect(map.snapshot().preamps == [1: 0, 2: 1, 3: 2])
    }
}

import MixerLink
@testable import Recording
import Testing

/// The Mixer's queue (#554): one gain move or undo at a time, in the order asked, because each Mix Hold plan reads the
/// Mixer, ramps and writes, and two at once could lose one's change to a setting they both compensate.
@MainActor
@Suite("Mixer queue")
struct MixerQueueTests {
    @Test("A job asked for while another is on the Mixer waits until that one is done; then they go in the order asked")
    func oneAtATimeInOrder() async throws {
        let queue = MixerQueue()
        var events: [String] = []
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()

        let first = Task { @MainActor in
            try await queue.run {
                events.append("first starts")
                enter.yield()
                for await _ in released { break }
                events.append("first ends")
            }
        }
        for await _ in entered { break }
        let second = Task { @MainActor in try await queue.run { events.append("second") } }
        let third = Task { @MainActor in try await queue.run { events.append("third") } }
        await Task.yield()
        release.yield()
        try await first.value
        try await second.value
        try await third.value
        // Without the queue, the second and third would run before the first ends.
        #expect(events == ["first starts", "first ends", "second", "third"])
    }

    @Test("A job that fails while another waits hands the Mixer on: the waiting one runs")
    func failureHandsOn() async throws {
        let queue = MixerQueue()
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        let first = Task { @MainActor in
            try await queue.run { () throws(MixerLinkProblem) in
                enter.yield()
                for await _ in released { break }
                throw MixerLinkProblem.networkUnreachable
            }
        }
        for await _ in entered { break }
        let second = Task { @MainActor in try await queue.run { "second ran" } }
        await Task.yield()
        release.yield()
        await #expect(throws: MixerLinkProblem.self) { try await first.value }
        #expect(try await second.value == "second ran")
    }

    @Test("A job that fails frees the Mixer for the next")
    func failureFreesTheMixer() async throws {
        let queue = MixerQueue()
        await #expect(throws: MixerLinkProblem.self) {
            try await queue.run { () throws(MixerLinkProblem) in throw MixerLinkProblem.networkUnreachable }
        }
        #expect(try await queue.run { 42 } == 42)
    }

    @Test("Jobs in different lanes run at once: the second starts while the first is still on the Mixer")
    func lanesAtOnce() async throws {
        let queue = MixerQueue()
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        let first = Task { @MainActor in
            try await queue.run(lane: 1) {
                enter.yield()
                for await _ in released { break }
            }
        }
        #expect(await ClipProtectionTests.next(entered), "the first lane's job starts")
        let second = Task { @MainActor in try await queue.run(lane: 2) { enter.yield() } }
        #expect(await ClipProtectionTests.next(entered), "the second lane's job starts while the first is under way")
        release.yield()
        try await first.value
        try await second.value
    }

    @Test("Jobs in one lane go one at a time, in the order asked")
    func oneLaneInOrder() async throws {
        let queue = MixerQueue()
        var events: [String] = []
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (asked, ask) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        let first = Task { @MainActor in
            try await queue.run(lane: 1) {
                events.append("first starts")
                enter.yield()
                for await _ in released { break }
                events.append("first ends")
            }
        }
        #expect(await ClipProtectionTests.next(entered), "the first job starts")
        // Each job is in the queue once it has said it asks: nothing suspends between the two.
        let second = Task { @MainActor in
            ask.yield()
            try await queue.run(lane: 1) { events.append("second") }
        }
        #expect(await ClipProtectionTests.next(asked))
        let third = Task { @MainActor in
            ask.yield()
            try await queue.run(lane: 1) { events.append("third") }
        }
        #expect(await ClipProtectionTests.next(asked))
        release.yield()
        try await first.value
        try await second.value
        try await third.value
        #expect(events == ["first starts", "first ends", "second", "third"])
    }
}

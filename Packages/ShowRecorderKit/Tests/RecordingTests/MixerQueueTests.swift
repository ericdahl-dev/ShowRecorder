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
}

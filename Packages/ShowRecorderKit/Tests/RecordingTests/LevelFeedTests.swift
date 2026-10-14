import Foundation
@testable import Recording
import Testing

/// How auto-gain measures a USB Channel's level (#554): in audio time, from the meter windows themselves, so a
/// stalled screen can't shorten it, and a measurement ends at once when the audio stops.
@MainActor
@Suite("Level feed")
struct LevelFeedTests {
    static let rate = 48_000

    /// A window of `seconds` of audio whose VU reading settles at `dbfs`.
    static func window(_ dbfs: Double, seconds: Double) -> ChannelLevel {
        ChannelLevel(peak: 1, meanRectified: Float(pow(10, dbfs / 20) / VUMeter.formFactor),
                     frames: Int(seconds * Double(rate)))
    }

    /// Starts measuring `usbChannel` and waits until the measurement is registered, so no window fed after it is
    /// missed; fails after 30 s rather than hanging (the main actor can be busy for seconds in a full run).
    static func start(_ feed: LevelFeed, usbChannel: Int = 1) async -> Task<Double?, Never> {
        let task = Task { await feed.measure(usbChannel: usbChannel) }
        let deadline = ContinuousClock.now + .seconds(30)
        while !feed.isMeasuring(usbChannel: usbChannel) {
            guard ContinuousClock.now < deadline else {
                Issue.record("the measurement never registered")
                break
            }
            await Task.yield()
        }
        return task
    }

    /// The measurement's result, or `.timedOut` after `seconds`, so a measurement that never ends fails the test
    /// instead of hanging the run (and the shared build lock with it).
    enum Outcome: Equatable { case level(Double?), timedOut }
    /// Not a task group: that waits for every child, so a measurement that never ends would hang it anyway.
    static func result(_ task: Task<Double?, Never>, within seconds: Double = 30) async -> Outcome {
        let (outcomes, sink) = AsyncStream<Outcome>.makeStream()
        Task { sink.yield(.level(await task.value)) }
        let timer = Task { try? await Task.sleep(for: .seconds(seconds)); sink.yield(.timedOut) }
        var first = outcomes.makeAsyncIterator()
        let outcome = await first.next() ?? .timedOut
        timer.cancel()
        task.cancel()
        return outcome
    }

    @Test("Skips the first 0.5 s of audio, then averages the next 2 s weighted by frames, with no clock involved")
    func audioTime() async throws {
        let feed = LevelFeed()
        let task = await Self.start(feed)

        // 0.5 s for the meter to follow a gain move: not counted.
        feed.meters([Self.window(-10, seconds: 0.25)], sampleRate: Self.rate)
        feed.meters([Self.window(-10, seconds: 0.25)], sampleRate: Self.rate)
        // Then 2 s: 1.5 s at -20 and 0.5 s at -26.
        feed.meters([Self.window(-20, seconds: 1.5)], sampleRate: Self.rate)
        feed.meters([Self.window(-26, seconds: 0.5)], sampleRate: Self.rate)

        guard case .level(let level?) = await Self.result(task) else {
            Issue.record("no level")
            return
        }
        #expect(abs(level - -21.5) < 0.1, "weighted by frames: \(level)")
    }

    @Test("One fat window of 1 s of audio (a stalled screen) still counts as 1 s")
    func fatWindow() async throws {
        let feed = LevelFeed()
        let task = await Self.start(feed)

        feed.meters([Self.window(-10, seconds: 0.5)], sampleRate: Self.rate)
        feed.meters([Self.window(-20, seconds: 1)], sampleRate: Self.rate)
        feed.meters([Self.window(-26, seconds: 1)], sampleRate: Self.rate)

        guard case .level(let level?) = await Self.result(task) else {
            Issue.record("no level")
            return
        }
        #expect(abs(level - -23) < 0.1, "\(level)")
    }

    @Test("No windows mid-measure (disarmed) ends it at once with no level")
    func noWindows() async throws {
        let feed = LevelFeed()
        let task = await Self.start(feed)

        feed.meters([Self.window(-20, seconds: 1)], sampleRate: Self.rate)
        feed.meters([], sampleRate: Self.rate)

        #expect(await Self.result(task) == .level(nil))
    }

    @Test("A sample-rate change mid-measure, or no sample rate (disarmed), ends it at once with no level")
    func sampleRateChange() async throws {
        let feed = LevelFeed()
        let changed = await Self.start(feed)
        feed.meters([Self.window(-20, seconds: 1)], sampleRate: Self.rate)
        feed.meters([Self.window(-20, seconds: 0.5)], sampleRate: 44_100)
        #expect(await Self.result(changed) == .level(nil))

        let none = await Self.start(feed)
        feed.meters([Self.window(-20, seconds: 1)], sampleRate: Self.rate)
        feed.meters([], sampleRate: nil)
        #expect(await Self.result(none) == .level(nil))
    }

    @Test("A change in the number of USB Channels mid-measure (another input) ends it at once with no level")
    func channelCountChange() async throws {
        let feed = LevelFeed()
        let task = await Self.start(feed)

        feed.meters([Self.window(-20, seconds: 1), Self.window(-20, seconds: 1)], sampleRate: Self.rate)
        feed.meters(Array(repeating: Self.window(-20, seconds: 1), count: 3), sampleRate: Self.rate)

        #expect(await Self.result(task) == .level(nil))
    }

    @Test("Canceling the measuring Task (the run was canceled) ends it at once with no level")
    func canceled() async throws {
        let feed = LevelFeed()
        let task = await Self.start(feed)
        feed.meters([Self.window(-20, seconds: 1)], sampleRate: Self.rate)

        task.cancel()

        #expect(await Self.result(task) == .level(nil))
    }
}

import AudioIO
import Foundation
@testable import Recording
import Testing

/// Take control through one seam (#551): the Take sequencer records, stops, places Markers, runs the Soundcheck Take
/// and starts and ends Shows, and tells every one of them on its events stream.
@MainActor
@Suite("Take control", .timeLimit(.minutes(10)))
struct TakeControlTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "TakeControlTests-\(UUID().uuidString)")

    final class FreeSpace: @unchecked Sendable {
        var bytes: Int64 = .max
    }

    func told(_ events: inout AsyncStream<TakeEvent>.Iterator, through last: TakeEvent) async -> [TakeEvent] {
        var seen: [TakeEvent] = []
        while let event = await events.next(isolation: #isolation) {
            seen.append(event)
            if event == last { break }
        }
        return seen
    }

    final class Clock: @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    func makeSequencer(free: FreeSpace = FreeSpace(), clock: Clock? = nil) -> (TakeSequencer, Recorder, FakeInputDevices) {
        let clock = clock ?? Clock(RecordingTakeTests.showDay)
        let recorder = Recorder(
            deviceFolder: root, now: { clock.date }, freeSpace: { _ in free.bytes }, destinationCheckInterval: nil)
        let source = FakeInputDevices([("xr18", 2)])
        return (TakeSequencer(recorder: recorder, devices: source, capsAt48k: { false }), recorder, source)
    }

    // MARK: - What already holds (characterization, before anything moves)

    @Test("A Soundcheck run tells the events stream its Take started and ended, Take 01 of the Soundcheck Show")
    func soundcheckTold() async throws {
        let (sequencer, _, source) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        let audio = try #require(source.opened.last)
        let feeding = Task { @MainActor in
            while !Task.isCancelled {
                audio.deliver([[Float](repeating: 0.5, count: 480), [Float](repeating: 0.5, count: 480)])
                sequencer.tick()
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        defer { feeding.cancel() }

        _ = await Soundcheck.run(
            sequencer: sequencer, mixer: nil, sources: [], expectedUSBChannels: nil, driveChosen: false, takeLength: .milliseconds(200))

        let seen = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped, isSoundcheck: true)))
        #expect(seen == [.takeStarted(take: 1), .takeEnded(TakeEnd(take: 1, reason: .stopped, isSoundcheck: true))])
    }

    @Test("A Take the recorder ends out of space is told once, with its reason")
    func outOfSpaceTold() async throws {
        let free = FreeSpace()
        let (sequencer, recorder, source) = makeSequencer(free: free)
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        sequencer.record(sources: [], allowance: nil)
        let audio = try #require(source.opened.last)
        try await deliverBlocks(2, to: audio, recorder)

        free.bytes = 0
        await recorder.checkDestinations()
        await recorder.checkDestinations()

        let seen = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .outOfSpace)))
        #expect(seen == [.takeStarted(take: 1), .takeEnded(TakeEnd(take: 1, reason: .outOfSpace))])
        #expect(!recorder.isRecording)
    }

    // MARK: - Through the sequencer

    @Test("Add Marker through the sequencer places a Marker and tells the events stream the count")
    func addMarker() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        sequencer.record(sources: [], allowance: nil)
        try await deliverBlocks(2, to: try #require(source.opened.last), recorder)

        sequencer.addMarker()
        sequencer.addMarker(named: "Chorus")

        let seen = await told(&events, through: .markerPlaced(count: 2))
        #expect(seen == [.takeStarted(take: 1), .markerPlaced(count: 1), .markerPlaced(count: 2)])
        #expect(recorder.takeMarkers.count == 2)
    }

    @Test("A Marker past the Take's limit (Free) is not placed and not told, so the Live Activity and watch don't count it (#705)")
    func addMarkerPastLimit() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        var allowance = TakeAllowance(recordedChannels: [1], showReport: false, reaperExport: false, namingByHand: false)
        allowance.markerLimit = 1
        sequencer.record(sources: [], allowance: allowance)
        try await deliverBlocks(2, to: try #require(source.opened.last), recorder)

        sequencer.addMarker()
        sequencer.addMarker()
        await sequencer.stop()

        let end = TakeEvent.takeEnded(TakeEnd(take: 1, reason: .stopped))
        #expect(await told(&events, through: end) == [.takeStarted(take: 1), .markerPlaced(count: 1), end])
        #expect(recorder.takeMarkers.count == 1)
    }

    @Test("Add Marker with no Take running does nothing and tells nothing")
    func addMarkerWithoutTake() async throws {
        let (sequencer, recorder, _) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed

        sequencer.addMarker()
        sequencer.record(sources: [], allowance: nil)

        #expect(await events.next() == .takeStarted(take: 1), "nothing told before the Take")
        #expect(recorder.takeMarkers.isEmpty)
    }

    @Test("A Take the recorder ends on its own leaves its reason in recordError, without a tick")
    func selfEndedTakeSaysWhy() async throws {
        let free = FreeSpace()
        let (sequencer, recorder, source) = makeSequencer(free: free)
        sequencer.arm()
        sequencer.record(sources: [], allowance: nil)
        try await deliverBlocks(2, to: try #require(source.opened.last), recorder)

        free.bytes = 0
        await recorder.checkDestinations()

        #expect(!recorder.isRecording)
        #expect(sequencer.recordError == TakeEnd.Reason.outOfSpace.message)
    }

    @Test("A stopped Take leaves recordError as it was")
    func stoppedTakeSaysNothing() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        sequencer.record(sources: [], allowance: nil)
        try await deliverBlocks(2, to: try #require(source.opened.last), recorder)

        await sequencer.stop()

        #expect(sequencer.recordError == nil)
    }

    @Test("Ending a Show through the sequencer tells the events stream its name and Take count")
    func endShow() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        try sequencer.startNewShow(name: "Friday", venue: "The Hall")
        for _ in 0..<2 {
            sequencer.record(sources: [], allowance: nil)
            try await deliverBlocks(2, to: try #require(source.opened.last), recorder)
            await sequencer.stop()
        }

        try sequencer.endShow()

        let seen = await told(&events, through: .showEnded(name: "2026-10-06 Friday", takeCount: 2))
        #expect(seen.last == .showEnded(name: "2026-10-06 Friday", takeCount: 2))
        #expect(recorder.currentShow == nil)
    }

    @Test("A Show can't be started or ended through the sequencer during a Take, and nothing is told")
    func noShowChangeDuringTake() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        sequencer.record(sources: [], allowance: nil)
        try await deliverBlocks(2, to: try #require(source.opened.last), recorder)
        let show = recorder.currentShow?.name

        #expect(throws: RecorderError.takeRunning) { try sequencer.endShow() }
        #expect(throws: RecorderError.takeRunning) { try sequencer.startNewShow(name: "Late", venue: "") }
        await sequencer.stop()

        #expect(recorder.currentShow?.name == show)
        let seen = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped)))
        #expect(seen == [.takeStarted(take: 1), .takeEnded(TakeEnd(take: 1, reason: .stopped))])
    }

    let saturday = Template(name: "Saturday", venue: nil, channelNames: [:], mixerNetworkName: nil, mixerAddress: "", preRollSeconds: 0)

    @Test("Starting a new Show over the open one tells the open one ended")
    func newShowEndsOpenOne() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        try sequencer.startNewShow(name: "Friday", venue: "")
        sequencer.record(sources: [], allowance: nil)
        try await deliverBlocks(2, to: try #require(source.opened.last), recorder)
        await sequencer.stop()

        _ = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped)))

        try sequencer.startNewShow(from: saturday)
        sequencer.record(sources: [], allowance: nil)

        let next = await events.next(isolation: #isolation)
        #expect(next == .showEnded(name: "2026-10-06 Friday", takeCount: 1))
        #expect(recorder.currentShow?.name == "2026-10-06 Saturday")
    }

    @Test("Readying the next Show over one idle for 6 hours tells the idle one ended")
    func preparingEndsIdleShow() async throws {
        let clock = Clock(RecordingTakeTests.showDay)
        let (sequencer, recorder, source) = makeSequencer(clock: clock)
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        try sequencer.startNewShow(name: "Friday", venue: "")
        sequencer.record(sources: [], allowance: nil)
        try await deliverBlocks(2, to: try #require(source.opened.last), recorder)
        await sequencer.stop()

        _ = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped)))

        clock.date = clock.date.addingTimeInterval(7 * 3600)
        #expect(sequencer.prepareNextShow(from: saturday))
        sequencer.record(sources: [], allowance: nil)

        let next = await events.next(isolation: #isolation)
        #expect(next == .showEnded(name: "2026-10-06 Friday", takeCount: 1))
    }

    // MARK: - The Soundcheck Take (PR 3)

    @Test("The Soundcheck Take runs through the sequencer and has a start time while it records, like any Take")
    func soundcheckTakeHasStartTime() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        let audio = try #require(source.opened.last)
        var startedWhileRecording = false
        let feeding = Task { @MainActor in
            while !Task.isCancelled {
                audio.deliver([[Float](repeating: 0.5, count: 480), [Float](repeating: 0.5, count: 480)])
                if recorder.isRecording, sequencer.takeStartedAt != nil { startedWhileRecording = true }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        defer { feeding.cancel() }

        _ = await Soundcheck.run(
            sequencer: sequencer, mixer: nil, sources: [], expectedUSBChannels: nil, driveChosen: false,
            takeLength: .milliseconds(200))

        #expect(startedWhileRecording)
        #expect(sequencer.takeStartedAt == nil, "and none once it ended")
    }

    @Test("A Soundcheck Take the recorder ends out of space is judged from its Copies, as before, and leaves no record error behind")
    func soundcheckOutOfSpace() async throws {
        let free = FreeSpace()
        let (sequencer, recorder, source) = makeSequencer(free: free)
        sequencer.arm()
        let audio = try #require(source.opened.last)
        let feeding = Task { @MainActor in
            while !Task.isCancelled {
                audio.deliver([[Float](repeating: 0.5, count: 480), [Float](repeating: 0.5, count: 480)])
                if recorder.isRecording, recorder.takeMarkers.isEmpty {
                    free.bytes = 0
                    await recorder.checkDestinations()
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        defer { feeding.cancel() }

        let steps = await Soundcheck.run(
            sequencer: sequencer, mixer: nil, sources: [], expectedUSBChannels: nil, driveChosen: false,
            takeLength: .milliseconds(300))

        let take = try #require(steps.first { $0.kind == .take })
        #expect(!take.message.contains("couldn't be recorded"), "the Take was recorded: \(take.message)")
        #expect(sequencer.recordError == nil, "the Soundcheck leaves the record screen's error as it found it")
    }

    // MARK: - One way in (PR 4)

    @Test("No synthetic Take start: a Take started on the recorder itself is never told as started, by a tick or at its end")
    func noSyntheticStart() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed

        try recorder.startTake()
        try await deliverBlocks(2, to: try #require(source.opened.last), recorder)
        sequencer.tick()
        await sequencer.stop()

        let next = await events.next(isolation: #isolation)
        #expect(next == .takeEnded(TakeEnd(take: 1, reason: .stopped)), "only the end is told: every Take that's told started went through await record()")
    }

    @Test("The Soundcheck Take's end is told as the Soundcheck's, so nothing after it offers Pro; any other Take's isn't")
    func soundcheckEndIsMarked() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        let audio = try #require(source.opened.last)
        let feeding = Task { @MainActor in
            while !Task.isCancelled {
                audio.deliver([[Float](repeating: 0.5, count: 480), [Float](repeating: 0.5, count: 480)])
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        defer { feeding.cancel() }

        _ = await Soundcheck.run(
            sequencer: sequencer, mixer: nil, sources: [], expectedUSBChannels: nil, driveChosen: false,
            takeLength: .milliseconds(200))
        let soundcheck = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped, isSoundcheck: true)))
        #expect(soundcheck.last == .takeEnded(TakeEnd(take: 1, reason: .stopped, isSoundcheck: true)))

        sequencer.record(sources: [], allowance: nil)
        try await deliverBlocks(2, to: audio, recorder)
        await sequencer.stop()
        let next = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped)))
        #expect(next.last == .takeEnded(TakeEnd(take: 1, reason: .stopped)), "the next Take isn't the Soundcheck's")
    }
}

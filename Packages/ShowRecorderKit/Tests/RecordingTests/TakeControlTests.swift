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
        let (sequencer, recorder, source) = makeSequencer()
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
            recorder: recorder, mixer: nil, sources: [], expectedUSBChannels: nil, driveChosen: false, takeLength: .milliseconds(200))

        let seen = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped)))
        #expect(seen == [.takeStarted(take: 1), .takeEnded(TakeEnd(take: 1, reason: .stopped))])
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
        recorder.checkDestinations()
        recorder.checkDestinations()

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
        recorder.checkDestinations()

        #expect(!recorder.isRecording)
        #expect(sequencer.recordError == TakeEnd.Reason.outOfSpace.message)
    }

    @Test("A stopped Take leaves recordError as it was")
    func stoppedTakeSaysNothing() async throws {
        let (sequencer, recorder, source) = makeSequencer()
        sequencer.arm()
        sequencer.record(sources: [], allowance: nil)
        try await deliverBlocks(2, to: try #require(source.opened.last), recorder)

        sequencer.stop()

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
            sequencer.stop()
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
        sequencer.stop()

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
        sequencer.stop()

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
        sequencer.stop()

        _ = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped)))

        clock.date = clock.date.addingTimeInterval(7 * 3600)
        #expect(sequencer.prepareNextShow(from: saturday))
        sequencer.record(sources: [], allowance: nil)

        let next = await events.next(isolation: #isolation)
        #expect(next == .showEnded(name: "2026-10-06 Friday", takeCount: 1))
    }
}

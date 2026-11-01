import AudioIO
import Foundation
@testable import Recording
import Testing

/// The Audio interfaces a test offers the sequencer, each backed by a `FakeAudioDevice`.
@MainActor
final class FakeInputDevices: InputDeviceSource {
    var choices: [DeviceChoice]
    /// The devices each choice opened, newest last.
    var opened: [FakeAudioDevice] = []
    /// What each `make` was asked for: the rate choice and whether it was capped at 48 kHz.
    var asked: [(chosen: Int?, capAt48k: Bool)] = []
    /// USB Channels an interface sends when it is opened again, where that changed (a reset, a new mixer setup).
    var reopensWith: [String: Int] = [:]
    /// Sample rates an interface opens at, where not 48 kHz.
    var rates: [String: Double] = [:]

    init(_ specs: [(id: String, channels: Int)] = [("xr18", 18)]) {
        choices = []
        choices = specs.map { choice(id: $0.id, channels: $0.channels) }
    }

    func choice(id: String, channels: Int, fails: Bool = false) -> DeviceChoice {
        DeviceChoice(
            info: InputDeviceInfo(id: id, name: id, inputChannelCount: channels, sampleRate: 48_000),
            name: id,
            make: { [self] chosen, capAt48k in
                asked.append((chosen, capAt48k))
                struct Refused: Error {}
                if fails { throw Refused() }
                let device = FakeAudioDevice(name: id, inputChannelCount: reopensWith[id] ?? channels, sampleRate: capAt48k ? 48_000 : rates[id] ?? 48_000)
                opened.append(device)
                return device
            })
    }

    func devices() -> [DeviceChoice] { choices }

    /// What the current iOS route opens as; nil makes it fail.
    var route: (channels: Int, sampleRate: Double)? = (18, 48_000)
    var routeOpened: [FakeAudioDevice] = []

    func currentRouteDevice(sampleRate: Int?) throws -> any AudioIODevice {
        struct NoRoute: Error {}
        guard let route else { throw NoRoute() }
        let device = FakeAudioDevice(name: "route", inputChannelCount: route.channels, sampleRate: route.sampleRate)
        routeOpened.append(device)
        return device
    }
}

/// A clock the test moves by hand.
@MainActor
final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
    func minutes(_ minutes: Double, after start: Date) { date = start.addingTimeInterval(minutes * 60) }
}

@MainActor
// Only a guard against a test that waits for an event that never comes: every event is told before a test reads
// it, so nothing here depends on time. Generous, because a busy Mac (#462) stretches every test.
@Suite("Take sequencer", .timeLimit(.minutes(10)))
struct TakeSequencerTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "TakeSequencerTests-\(UUID().uuidString)")

    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// The events told up to and including `last`. An event that never comes waits until the suite's time limit
    /// fails the test.
    func told(_ events: inout AsyncStream<TakeEvent>.Iterator, through last: TakeEvent) async -> [TakeEvent] {
        var seen: [TakeEvent] = []
        while let event = await events.next(isolation: #isolation) {
            seen.append(event)
            if event == last { break }
        }
        return seen
    }

    func makeSequencer(_ source: FakeInputDevices = FakeInputDevices(), capsAt48k: Bool = false, now: @escaping () -> Date = Date.init) -> (TakeSequencer, Recorder) {
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        return (TakeSequencer(recorder: recorder, devices: source, capsAt48k: { capsAt48k }, now: now), recorder)
    }

    @Test("When the sequencer goes away its events stream ends, so a listener's loop finishes")
    func streamEndsWithTheSequencer() async {
        var events: AsyncStream<TakeEvent>.Iterator
        do {
            let (sequencer, _) = makeSequencer()
            events = sequencer.events.makeAsyncIterator()
        }
        let next = await events.next(isolation: #isolation)
        #expect(next == nil)
    }

    @Test("Getting ready opens the selected Audio interface and Gets the recorder ready on it")
    func getsReadyTheSelectedInterface() {
        let source = FakeInputDevices([("built-in", 1), ("xr18", 18)])
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.selectedDeviceID = "xr18"

        sequencer.getReady()

        #expect(recorder.isReady)
        #expect(recorder.usbChannelCount == 18)
        #expect(sequencer.readyDevice?.id == "xr18")
    }

    @Test("The interface opens at the sample rate choice, capped at 48 kHz when the tier says so")
    func opensAtTheRateChoice() {
        let source = FakeInputDevices()
        let (sequencer, _) = makeSequencer(source, capsAt48k: true)
        sequencer.sampleRateChoice = 96_000

        sequencer.getReady()

        #expect(source.asked.map(\.chosen) == [96_000])
        #expect(source.asked.map(\.capAt48k) == [true])
    }

    @Test("An interface that won't open says why, forgets the Ready interface, and the next get-ready that works clears it")
    func getReadyFailure() {
        let source = FakeInputDevices()
        source.choices.append(source.choice(id: "broken", channels: 2, fails: true))
        let (sequencer, _) = makeSequencer(source)
        sequencer.getReady()
        sequencer.selectedDeviceID = "broken"

        sequencer.getReady()

        #expect(sequencer.getReadyError?.hasPrefix("Couldn't start broken: ") == true)
        #expect(sequencer.readyDevice == nil)

        sequencer.selectedDeviceID = "xr18"
        sequencer.getReady()
        #expect(sequencer.getReadyError == nil)
        #expect(sequencer.readyDevice?.id == "xr18")
    }

    @Test("Getting ready with no interface selected stands down")
    func getReadyWithNothingSelected() {
        let (sequencer, recorder) = makeSequencer()
        sequencer.getReady()
        sequencer.selectedDeviceID = nil

        sequencer.getReady()

        #expect(!recorder.isReady)
        #expect(sequencer.readyDevice == nil)
    }

    @Test("Getting ready tells the events stream which interface is Ready")
    func readyEvent() async {
        let (sequencer, _) = makeSequencer()
        var events = sequencer.events.makeAsyncIterator()

        sequencer.getReady()

        #expect(await events.next() == .ready(sequencer.readyDevice!))
    }

    @Test("Choosing an interface gets it ready; choosing the one already Ready leaves it alone")
    func select() {
        let source = FakeInputDevices([("xr18", 18), ("built-in", 1)])
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.getReady()

        sequencer.select("xr18")
        #expect(source.opened.count == 1)

        sequencer.select("built-in")
        #expect(sequencer.selectedDeviceID == "built-in")
        #expect(sequencer.readyDevice?.id == "built-in")
        #expect(recorder.usbChannelCount == 1)
    }

    @Test("Record starts a Take and notes when it started")
    func record() throws {
        let (sequencer, recorder) = makeSequencer(now: { start })
        sequencer.getReady()

        let started = sequencer.record(sources: [], allowance: nil)

        #expect(started)
        #expect(recorder.isRecording)
        #expect(sequencer.takeStartedAt == start)
        #expect(sequencer.recordError == nil)
    }

    @Test("A record press that can't start a Take says why")
    func recordFailure() {
        let (sequencer, _) = makeSequencer()

        #expect(!sequencer.record(sources: [], allowance: nil))
        #expect(sequencer.recordError?.hasPrefix("Couldn't start recording: ") == true)
        #expect(sequencer.takeStartedAt == nil)
    }

    @Test("A second record press during a Take changes nothing and announces nothing (#695)")
    func recordDuringATake() async {
        var clock = start
        let (sequencer, recorder) = makeSequencer(now: { clock })
        sequencer.getReady()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .ready
        sequencer.record(sources: [], allowance: nil)
        #expect(await events.next() == .takeStarted(take: 1))
        sequencer.recordError = "An earlier problem"
        clock = start.addingTimeInterval(90)

        let started = sequencer.record(sources: [], allowance: nil, soundcheck: true)

        #expect(!started)
        #expect(recorder.isRecording)
        #expect(sequencer.takeStartedAt == start)
        #expect(sequencer.recordError == "An earlier problem")
        // A later event proves no second `.takeStarted` was queued ahead of it, and the Take still ends
        // as a real Take, not a Soundcheck.
        await sequencer.stop()
        #expect(await events.next() == .takeEnded(TakeEnd(take: 1, reason: .stopped)))
    }

    @Test("Stop ends the Take and clears its start time")
    func stop() async throws {
        let (sequencer, recorder) = makeSequencer()
        sequencer.getReady()
        sequencer.record(sources: [], allowance: nil)

        await sequencer.stop()

        #expect(!recorder.isRecording)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped))
        #expect(sequencer.takeStartedAt == nil)
    }

    @Test("Record tells the events stream which Take started")
    func takeStartedEvent() async {
        let (sequencer, _) = makeSequencer()
        sequencer.getReady()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .ready

        sequencer.record(sources: [], allowance: nil)

        #expect(await events.next() == .takeStarted(take: 1))
    }

    @Test("Stop tells the events stream which Take ended and why")
    func takeEndedEvent() async {
        let (sequencer, _) = makeSequencer()
        sequencer.getReady()
        sequencer.record(sources: [], allowance: nil)
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .ready
        _ = await events.next()  // .takeStarted

        await sequencer.stop()

        #expect(await events.next() == .takeEnded(TakeEnd(take: 1, reason: .stopped)))
    }

    @Test("A Take started with record is told once, not again on the next tick")
    func recordThenTick() async {
        let (sequencer, _) = makeSequencer()
        sequencer.getReady()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .ready

        sequencer.record(sources: [], allowance: nil)
        sequencer.tick()
        await sequencer.stop()

        #expect(await events.next() == .takeStarted(take: 1))
        #expect(await events.next() == .takeEnded(TakeEnd(take: 1, reason: .stopped)))
    }

    @Test("After every get-ready attempt the App hears of it: the device when it worked, nil when it failed, nothing with no selection")
    func didGetReady() {
        let source = FakeInputDevices()
        source.choices.append(source.choice(id: "broken", channels: 2, fails: true))
        let (sequencer, _) = makeSequencer(source)
        var heard: [String?] = []
        sequencer.didGetReady = { device in heard.append(device?.name) }

        sequencer.getReady()
        sequencer.selectedDeviceID = "broken"
        sequencer.getReady()
        sequencer.selectedDeviceID = nil
        sequencer.getReady()

        #expect(heard == ["xr18", nil])
    }

    @Test("A screen that appears before the first get-ready was tried doesn't Get ready early; after it, it gets ready one that isn't")
    func appearBeforeStart() {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)

        sequencer.screenAppeared()
        #expect(!recorder.isReady)

        sequencer.start()
        #expect(recorder.isReady)
    }

    @Test("A screen that appears leaves a Ready recorder alone, because Getting ready again would stop a Take")
    func appearWhileReady() {
        let source = FakeInputDevices()
        let (sequencer, _) = makeSequencer(source)
        sequencer.start()

        sequencer.screenAppeared()

        #expect(source.opened.count == 1)
    }

    @Test("When the screen goes away during a Take, nothing ends the Take")
    func disappearDuringATake() {
        let (sequencer, recorder) = makeSequencer()
        sequencer.start()
        sequencer.record(sources: [], allowance: nil)

        sequencer.screenDisappeared()

        #expect(recorder.isRecording)
    }

    @Test("When the screen goes away with no Take, the recorder stands down so the input isn't held for nothing")
    func disappearWhileOnlyReady() {
        let (sequencer, recorder) = makeSequencer()
        sequencer.start()

        sequencer.screenDisappeared()

        #expect(!recorder.isReady)
    }

    @Test("A screen that goes away and stands down tells the events stream why")
    func screenGoneEvent() async {
        let (sequencer, _) = makeSequencer()
        sequencer.start()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .ready

        sequencer.screenDisappeared()

        #expect(await events.next() == .stoodDown(reason: .screenGone))
    }

    @Test("Closing a window while a Take is running asks first; with no Take it just closes")
    func closingTheWindow() {
        let (sequencer, _) = makeSequencer()
        sequencer.start()
        #expect(sequencer.windowCloseRequested() == .close)

        sequencer.record(sources: [], allowance: nil)
        #expect(sequencer.windowCloseRequested() == .askToStop)
    }

    @Test("A Marker past the Free limit says it wasn't placed, so the watch doesn't confirm it (#882)")
    func markerPastTheLimitSaysSo() async throws {
        let source = FakeInputDevices([("fake", 1)])
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()
        var allowance = TakeAllowance(recordedChannels: [1], showReport: false, reaperExport: false, namingByHand: false)
        allowance.markerLimit = 3
        sequencer.record(sources: [], allowance: allowance)
        for _ in 1...3 { #expect(sequencer.addMarker()) }
        #expect(!sequencer.addMarker())
        #expect(recorder.takeMarkers.count == 3)
        await sequencer.stop()
        #expect(!sequencer.addMarker(), "not recording")
    }

    @Test("Quitting the Mac app during a Take asks first, like closing the window; otherwise it just quits")
    func quitAsksDuringATake() {
        let (sequencer, _) = makeSequencer()
        sequencer.start()
        #expect(sequencer.quitRequested() == .quit)

        sequencer.record(sources: [], allowance: nil)
        #expect(sequencer.quitRequested() == .askToStop)
    }

    @Test("Tearing down the screen and building it again during a Take leaves the Take, its Markers and its Stem untouched")
    func screenRebuiltDuringATake() async throws {
        let source = FakeInputDevices([("fake", 1)])
        let (sequencer, recorder) = makeSequencer(source)
        func sample(_ value: Int32) -> Float { Float(value) / 8_388_608 }
        sequencer.start()
        let device = try #require(source.opened.last)
        sequencer.record(sources: [], allowance: nil)
        device.deliver([[sample(1), sample(2)]])
        recorder.addMarker(named: "Verse")

        // The screen goes away and a new one appears, as when iOS discards and rebuilds a scene.
        sequencer.screenDisappeared()
        sequencer.screenAppeared()

        #expect(recorder.isRecording)
        #expect(recorder.takeMarkers.map(\.name) == ["Verse"])
        device.deliver([[sample(3), sample(4)]])
        await sequencer.stop()

        let stem = try ParsedStem(contentsOf: try #require(recorder.currentShow).folder.appending(path: "Take 01/01 USB 01.wav"))
        #expect(stem.samples == [1, 2, 3, 4])
    }

    @Test("A Ready recorder left in the background stands down after 30 minutes with no Take, not before")
    func idleStandDown() {
        let clock = TestClock(start)
        let (sequencer, recorder) = makeSequencer(now: { clock.date })
        sequencer.start()
        sequencer.appMovedToBackground()

        clock.minutes(29.99, after: start)
        sequencer.tick()
        #expect(recorder.isReady)

        clock.minutes(IdleStandDown.limit / 60, after: start)
        sequencer.tick()
        #expect(!recorder.isReady)
        #expect(sequencer.stoodDownForIdle)
        #expect(sequencer.readyDevice == nil)
    }

    @Test("A Take never stands down, and counts as use: the 30 minutes start again after it")
    func takeResetsIdle() async {
        let clock = TestClock(start)
        let (sequencer, recorder) = makeSequencer(now: { clock.date })
        sequencer.start()
        sequencer.appMovedToBackground()
        clock.minutes(10, after: start)
        sequencer.record(sources: [], allowance: nil)

        clock.minutes(45, after: start)
        sequencer.tick()
        #expect(recorder.isRecording)
        await sequencer.stop()

        clock.minutes(74, after: start)
        sequencer.tick()
        #expect(recorder.isReady)

        clock.minutes(75, after: start)
        sequencer.tick()
        #expect(!recorder.isReady)
    }

    @Test("Coming back to the app after an idle stand-down gets ready again")
    func comingBackGetsReadyAgain() {
        let clock = TestClock(start)
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source, now: { clock.date })
        sequencer.start()
        sequencer.appMovedToBackground()
        clock.minutes(30, after: start)
        sequencer.tick()

        sequencer.appBecameActive()

        #expect(recorder.isReady)
        #expect(!sequencer.stoodDownForIdle)
        #expect(source.opened.count == 2)
    }

    @Test("Get ready again from the alert gets ready and clears the idle stand-down, without starting a Take")
    func getReadyAgain() {
        let clock = TestClock(start)
        let (sequencer, recorder) = makeSequencer(now: { clock.date })
        sequencer.start()
        sequencer.appMovedToBackground()
        clock.minutes(30, after: start)
        sequencer.tick()

        sequencer.getReadyAgain()

        #expect(recorder.isReady)
        #expect(!recorder.isRecording)
        #expect(!sequencer.stoodDownForIdle)
    }

    @Test("An idle stand-down tells the events stream why")
    func idleEvent() async {
        let clock = TestClock(start)
        let (sequencer, _) = makeSequencer(now: { clock.date })
        sequencer.start()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .ready
        sequencer.appMovedToBackground()
        clock.minutes(30, after: start)

        sequencer.tick()

        #expect(await events.next() == .stoodDown(reason: .idle))
    }

    @Test("Take 01 of a new Show is told too, though it ends like Take 01 of the last one")
    func sameTakeNumberInANewShow() async throws {
        let (sequencer, recorder) = makeSequencer()
        sequencer.start()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .ready
        sequencer.record(sources: [], allowance: nil)
        await sequencer.stop()
        try recorder.endShow()

        sequencer.record(sources: [], allowance: nil)
        await sequencer.stop()
        sequencer.record(sources: [], allowance: nil)

        #expect(await events.next() == .takeStarted(take: 1))
        #expect(await events.next() == .takeEnded(TakeEnd(take: 1, reason: .stopped)))
        #expect(await events.next() == .takeStarted(take: 1))
        #expect(await events.next() == .takeEnded(TakeEnd(take: 1, reason: .stopped)))
        #expect(await events.next() == .takeStarted(take: 2))
    }

    @Test("With no one listening, the events stream keeps only the newest events, not every one since launch")
    func eventsBufferIsBounded() async {
        let (sequencer, _) = makeSequencer()
        sequencer.getReady()
        for _ in 0..<20 {
            sequencer.record(sources: [], allowance: nil)
            await sequencer.stop()
        }
        var events = sequencer.events.makeAsyncIterator()

        // 41 events were told; only the newest 32 are kept, so the .ready at the start is gone.
        var kept: [TakeEvent] = []
        for _ in 0..<TakeSequencer.eventBufferSize { kept.append(await events.next()!) }
        #expect(kept.first == .takeStarted(take: 5))
        #expect(kept.last == .takeEnded(TakeEnd(take: 20, reason: .stopped)))
    }

    @Test("A Take the recorder ends on its own is told at once, without waiting for a tick")
    func takeEndedWithoutATick() async throws {
        let (sequencer, recorder) = makeSequencer()
        sequencer.start()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .ready
        sequencer.record(sources: [], allowance: nil)
        _ = await events.next()  // .takeStarted

        try await recorder.restartInput(on: FakeAudioDevice(inputChannelCount: 2))
        #expect(sequencer.takeStartedAt == nil)
        sequencer.screenDisappeared()

        #expect(await told(&events, through: .stoodDown(reason: .screenGone)) == [
            .takeEnded(TakeEnd(take: 1, reason: .inputChanged)), .stoodDown(reason: .screenGone),
        ])
    }

    // MARK: - Interruptions

    @Test("An interruption during a Take stops input; when it ends, input restarts on the same device and the Take goes on")
    func interruptionDuringATake() async throws {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()
        let device = try #require(source.opened.last)
        sequencer.record(sources: [], allowance: nil)

        await sequencer.handle(.interruptionBegan(reason: .other))
        device.stop()  // The system stops input.
        await sequencer.handle(.interruptionEnded(shouldResume: true))

        #expect(device.isRunning)
        #expect(recorder.isRecording)
        #expect(!sequencer.interruptions.isInputStopped)
        #expect(sequencer.interruptions.notice == "Input is back. Audio from the interruption is missing from this Take.")
    }

    @Test("Input stopping and coming back are told, once each")
    func inputStoppedAndRestartedAreTold() async throws {
        let source = FakeInputDevices()
        let (sequencer, _) = makeSequencer(source)
        sequencer.start()
        let device = try #require(source.opened.last)
        sequencer.record(sources: [], allowance: nil)
        var events = sequencer.events.makeAsyncIterator()

        await sequencer.handle(.interruptionBegan(reason: .other))
        device.stop()
        await sequencer.handle(.interruptionEnded(shouldResume: true))

        await sequencer.stop()

        let told = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped)))
        #expect(told.filter { $0 == .inputStopped }.count == 1)
        #expect(told.filter { $0 == .inputRestarted }.count == 1)
    }

    @Test("A Take started after an interruption that ended without resuming restarts input (#877)")
    func recordRestartsStoppedInput() async throws {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()
        let device = try #require(source.opened.last)
        await sequencer.handle(.interruptionBegan(reason: .other))
        device.stop()
        await sequencer.handle(.interruptionEnded(shouldResume: false))
        #expect(!device.isRunning, "Ready, not recording: nothing restarts input yet")

        sequencer.record(sources: [], allowance: nil)

        try await waitUntil { device.isRunning }
        #expect(recorder.isRecording)
        #expect(!sequencer.interruptions.isInputStopped)
    }

    @Test("Starting a Take clears an interruption's old notice")
    func recordClearsTheNotice() async throws {
        let source = FakeInputDevices()
        let (sequencer, _) = makeSequencer(source)
        sequencer.start()
        let device = try #require(source.opened.last)
        sequencer.record(sources: [], allowance: nil)
        await sequencer.handle(.interruptionBegan(reason: .other))
        device.stop()
        await sequencer.handle(.interruptionEnded(shouldResume: true))
        await sequencer.stop()
        #expect(sequencer.interruptions.notice != nil)

        sequencer.record(sources: [], allowance: nil)

        #expect(sequencer.interruptions.notice == nil)
    }

    @Test("A new iOS route between Takes gets ready again on the selected interface")
    func routeChangeBetweenTakes() async {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()
        #expect(source.opened.count == 1)

        await sequencer.routeChanged()

        #expect(source.opened.count == 2)
        #expect(recorder.isReady && !recorder.isRecording)
    }

    @Test("A new iOS route during a Take moves the Take onto it: same format goes on, another ends as an input change")
    func routeChangeDuringATake() async throws {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()
        sequencer.record(sources: [], allowance: nil)

        await sequencer.routeChanged()
        #expect(recorder.isRecording)
        #expect(try #require(source.routeOpened.last).isRunning)
        #expect(sequencer.recordError == nil)

        source.route = (2, 48_000)
        await sequencer.routeChanged()
        #expect(!recorder.isRecording)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .inputChanged))
        #expect(sequencer.recordError == TakeEnd.Reason.inputChanged.message)
    }

    @Test("A move that fails leaves input stopped, and the next route change tries again and brings it back")
    func failedRouteMoveRetries() async throws {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()
        sequencer.record(sources: [], allowance: nil)

        source.route = nil
        await sequencer.routeChanged()
        #expect(sequencer.interruptions.isInputStopped)
        #expect(recorder.isRecording)

        source.route = (18, 48_000)
        await sequencer.routeChanged()
        #expect(!sequencer.interruptions.isInputStopped)
        #expect(recorder.isRecording)
        #expect(try #require(source.routeOpened.last).isRunning)
    }

    @Test("A restart that fails leaves input stopped and says so in the notice")
    func failedRestart() async {
        let (sequencer, _) = makeSequencer()  // Nothing Ready, so there's nothing to restart.

        await sequencer.handle(.interruptionBegan(reason: .other))
        await sequencer.handle(.interruptionEnded(shouldResume: true))

        #expect(sequencer.interruptions.isInputStopped)
        #expect(sequencer.interruptions.notice?.hasPrefix("Couldn't restart audio input: ") == true)
    }

    @Test("A media reset during a Take opens the interface again at the Take's rate, uncapped, and the Take goes on when the format matches")
    func mediaResetSameFormat() async throws {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source, capsAt48k: true)
        sequencer.start()
        sequencer.record(sources: [], allowance: nil)
        var heard: [String?] = []
        sequencer.didGetReady = { device in heard.append(device?.name) }

        await sequencer.handle(.mediaServicesReset)

        #expect(source.opened.count == 2)
        #expect(source.asked.last?.chosen == 48_000)
        #expect(source.asked.last?.capAt48k == false)
        #expect(try #require(source.opened.last).isRunning)
        #expect(recorder.isRecording)
        #expect(!sequencer.interruptions.isInputStopped)
        #expect(heard == ["xr18"])
    }

    @Test("A media reset that brings the input back in another format ends the Take as an input change, told once by the notice")
    func mediaResetOtherFormat() async throws {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()
        sequencer.record(sources: [], allowance: nil)
        source.reopensWith["xr18"] = 2

        await sequencer.handle(.mediaServicesReset)

        #expect(!recorder.isRecording)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .inputChanged))
        #expect(recorder.isReady)
        #expect(recorder.usbChannelCount == 2)
        #expect(sequencer.interruptions.notice == "The system reset its audio and the input changed, so the Take ended and was saved. Press record to start the next Take.")
        #expect(sequencer.recordError == nil)
    }

    @Test("The Ready interface unplugged during a Take: the Take ends as an input change, the message says so, and the recorder stands down")
    func readyInterfaceUnpluggedDuringATake() async {
        let source = FakeInputDevices([("built-in", 1), ("xr18", 18)])
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.selectedDeviceID = "xr18"
        sequencer.start()
        sequencer.record(sources: [], allowance: nil)
        var events = sequencer.events.makeAsyncIterator()

        source.choices.removeAll { $0.id == "xr18" }
        await sequencer.deviceListChanged()

        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .inputChanged))
        #expect(sequencer.recordError == "xr18 was disconnected during the Take. Recording stopped and the Stems recorded so far were saved.")
        #expect(!recorder.isReady)
        #expect(sequencer.readyDevice == nil)
        let told = await told(&events, through: .stoodDown(reason: .deviceLost))
        #expect(told.contains(.takeEnded(TakeEnd(take: 1, reason: .inputChanged))))
    }

    @Test("The Ready interface changes format during a Take: the Take ends as an input change and the recorder gets ready again on the new format")
    func readyInterfaceChangesFormatDuringATake() async {
        let source = FakeInputDevices([("xr18", 18)])
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()
        sequencer.record(sources: [], allowance: nil)

        source.choices = [source.choice(id: "xr18", channels: 12)]
        await sequencer.deviceListChanged()

        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .inputChanged))
        #expect(sequencer.recordError == "xr18 now sends 12 USB Channels during the Take. Recording stopped and the Stems recorded so far were saved. Press record to start a new Take.")
        #expect(recorder.isReady && !recorder.isRecording)
        #expect(recorder.usbChannelCount == 12)
    }

    @Test("A Pre-roll or sample rate change gets ready again between Takes, never during one (Show-Safe)")
    func settingsChangeGetsReadyAgainOnlyBetweenTakes() {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()

        sequencer.settingsChanged()
        #expect(source.opened.count == 2)

        sequencer.record(sources: [], allowance: nil)
        sequencer.settingsChanged()
        #expect(source.opened.count == 2)
        #expect(recorder.isRecording)
    }

    @Test("When the tier comes to cap at 48 kHz, an input running faster gets ready again between Takes; a running Take keeps its rate")
    func tierCapGetsReadyAgainOnlyBetweenTakes() async {
        let source = FakeInputDevices()
        source.rates["xr18"] = 96_000
        var capped = false
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        let sequencer = TakeSequencer(recorder: recorder, devices: source, capsAt48k: { capped })
        sequencer.start()
        #expect(recorder.sampleRate == 96_000)

        sequencer.record(sources: [], allowance: nil)
        capped = true
        sequencer.tierChanged()
        #expect(recorder.isRecording && recorder.sampleRate == 96_000)

        await sequencer.stop()
        sequencer.tierChanged()
        #expect(recorder.sampleRate == 48_000)
        #expect(source.asked.last?.capAt48k == true)
    }

    @Test("A media reset that comes back in another format tells the new get-ready")
    func mediaResetOtherFormatTellsTheGetReady() async {
        let source = FakeInputDevices()
        let (sequencer, _) = makeSequencer(source)
        sequencer.start()
        sequencer.record(sources: [], allowance: nil)
        var events = sequencer.events.makeAsyncIterator()
        source.reopensWith["xr18"] = 2

        await sequencer.handle(.mediaServicesReset)
        await sequencer.stop()  // nothing to stop: a known last event to read up to
        sequencer.screenDisappeared()

        let told = await told(&events, through: .stoodDown(reason: .screenGone))
        #expect(told.filter { if case .ready = $0 { true } else { false } }.count == 2, "the first get-ready, then the one on the new format")
    }
}

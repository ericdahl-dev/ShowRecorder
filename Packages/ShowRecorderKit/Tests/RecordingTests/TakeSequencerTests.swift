import AudioIO
import Foundation
import Recording
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
                let device = FakeAudioDevice(name: id, inputChannelCount: reopensWith[id] ?? channels)
                opened.append(device)
                return device
            })
    }

    func devices() -> [DeviceChoice] { choices }
}

/// A clock the test moves by hand.
@MainActor
final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
    func minutes(_ minutes: Double, after start: Date) { date = start.addingTimeInterval(minutes * 60) }
}

@MainActor
@Suite("Take sequencer", .timeLimit(.minutes(1)))
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

    @Test("Arming opens the selected Audio interface and Arms the recorder on it")
    func armsTheSelectedInterface() {
        let source = FakeInputDevices([("built-in", 1), ("xr18", 18)])
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.selectedDeviceID = "xr18"

        sequencer.arm()

        #expect(recorder.isArmed)
        #expect(recorder.usbChannelCount == 18)
        #expect(sequencer.armedDevice?.id == "xr18")
    }

    @Test("The interface opens at the sample rate choice, capped at 48 kHz when the tier says so")
    func opensAtTheRateChoice() {
        let source = FakeInputDevices()
        let (sequencer, _) = makeSequencer(source, capsAt48k: true)
        sequencer.sampleRateChoice = 96_000

        sequencer.arm()

        #expect(source.asked.map(\.chosen) == [96_000])
        #expect(source.asked.map(\.capAt48k) == [true])
    }

    @Test("An interface that won't open says why, forgets the Armed interface, and the next Arm that works clears it")
    func armFailure() {
        let source = FakeInputDevices()
        source.choices.append(source.choice(id: "broken", channels: 2, fails: true))
        let (sequencer, _) = makeSequencer(source)
        sequencer.arm()
        sequencer.selectedDeviceID = "broken"

        sequencer.arm()

        #expect(sequencer.armError?.hasPrefix("Couldn't start broken: ") == true)
        #expect(sequencer.armedDevice == nil)

        sequencer.selectedDeviceID = "xr18"
        sequencer.arm()
        #expect(sequencer.armError == nil)
        #expect(sequencer.armedDevice?.id == "xr18")
    }

    @Test("Arming with no interface selected disarms")
    func armWithNothingSelected() {
        let (sequencer, recorder) = makeSequencer()
        sequencer.arm()
        sequencer.selectedDeviceID = nil

        sequencer.arm()

        #expect(!recorder.isArmed)
        #expect(sequencer.armedDevice == nil)
    }

    @Test("Arming tells the events stream which interface is Armed")
    func armedEvent() async {
        let (sequencer, _) = makeSequencer()
        var events = sequencer.events.makeAsyncIterator()

        sequencer.arm()

        #expect(await events.next() == .armed(sequencer.armedDevice!))
    }

    @Test("Choosing an interface Arms it; choosing the one already Armed leaves it alone")
    func select() {
        let source = FakeInputDevices([("xr18", 18), ("built-in", 1)])
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.arm()

        sequencer.select("xr18")
        #expect(source.opened.count == 1)

        sequencer.select("built-in")
        #expect(sequencer.selectedDeviceID == "built-in")
        #expect(sequencer.armedDevice?.id == "built-in")
        #expect(recorder.usbChannelCount == 1)
    }

    @Test("Record starts a Take and notes when it started")
    func record() throws {
        let (sequencer, recorder) = makeSequencer(now: { start })
        sequencer.arm()

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

    @Test("Stop ends the Take and clears its start time")
    func stop() throws {
        let (sequencer, recorder) = makeSequencer()
        sequencer.arm()
        sequencer.record(sources: [], allowance: nil)

        sequencer.stop()

        #expect(!recorder.isRecording)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped))
        #expect(sequencer.takeStartedAt == nil)
    }

    @Test("Record tells the events stream which Take started")
    func takeStartedEvent() async {
        let (sequencer, _) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed

        sequencer.record(sources: [], allowance: nil)

        #expect(await events.next() == .takeStarted(take: 1))
    }

    @Test("Stop tells the events stream which Take ended and why")
    func takeEndedEvent() async {
        let (sequencer, _) = makeSequencer()
        sequencer.arm()
        sequencer.record(sources: [], allowance: nil)
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        _ = await events.next()  // .takeStarted

        sequencer.stop()

        #expect(await events.next() == .takeEnded(TakeEnd(take: 1, reason: .stopped)))
    }

    @Test("A Take started without the sequencer (the Soundcheck) is told on the next tick, once")
    func takeStartedElsewhere() async throws {
        let (sequencer, recorder) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed

        try recorder.startTake()
        sequencer.tick()
        sequencer.tick()
        sequencer.stop()

        #expect(await events.next() == .takeStarted(take: 1))
        #expect(await events.next() == .takeEnded(TakeEnd(take: 1, reason: .stopped)))
    }

    @Test("A Take started with record is told once, not again on the next tick")
    func recordThenTick() async {
        let (sequencer, _) = makeSequencer()
        sequencer.arm()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed

        sequencer.record(sources: [], allowance: nil)
        sequencer.tick()
        sequencer.stop()

        #expect(await events.next() == .takeStarted(take: 1))
        #expect(await events.next() == .takeEnded(TakeEnd(take: 1, reason: .stopped)))
    }

    @Test("After every Arm attempt the App hears of it: the device when it worked, nil when it failed, nothing with no selection")
    func didArm() {
        let source = FakeInputDevices()
        source.choices.append(source.choice(id: "broken", channels: 2, fails: true))
        let (sequencer, _) = makeSequencer(source)
        var heard: [String?] = []
        sequencer.didArm = { device in heard.append(device?.name) }

        sequencer.arm()
        sequencer.selectedDeviceID = "broken"
        sequencer.arm()
        sequencer.selectedDeviceID = nil
        sequencer.arm()

        #expect(heard == ["xr18", nil])
    }

    @Test("A screen that appears before the first Arm was tried doesn't Arm early; after it, it Arms one that isn't")
    func appearBeforeStart() {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)

        sequencer.screenAppeared()
        #expect(!recorder.isArmed)

        sequencer.start()
        #expect(recorder.isArmed)
    }

    @Test("A screen that appears leaves an Armed recorder alone, because Arming again would stop a Take")
    func appearWhileArmed() {
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

    @Test("When the screen goes away with no Take, the recorder disarms so the input isn't held for nothing")
    func disappearWhileOnlyArmed() {
        let (sequencer, recorder) = makeSequencer()
        sequencer.start()

        sequencer.screenDisappeared()

        #expect(!recorder.isArmed)
    }

    @Test("A screen that goes away and disarms tells the events stream why")
    func screenGoneEvent() async {
        let (sequencer, _) = makeSequencer()
        sequencer.start()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed

        sequencer.screenDisappeared()

        #expect(await events.next() == .disarmed(reason: .screenGone))
    }

    @Test("Closing a window while a Take is running asks first; with no Take it just closes")
    func closingTheWindow() {
        let (sequencer, _) = makeSequencer()
        sequencer.start()
        #expect(sequencer.windowCloseRequested() == .close)

        sequencer.record(sources: [], allowance: nil)
        #expect(sequencer.windowCloseRequested() == .askToStop)
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
    func screenRebuiltDuringATake() throws {
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
        sequencer.stop()

        let stem = try ParsedStem(contentsOf: try #require(recorder.currentShow).folder.appending(path: "Take 01/01 USB 01.wav"))
        #expect(stem.samples == [1, 2, 3, 4])
    }

    @Test("An Armed recorder left in the background disarms after 30 minutes with no Take, not before")
    func idleDisarm() {
        let clock = TestClock(start)
        let (sequencer, recorder) = makeSequencer(now: { clock.date })
        sequencer.start()
        sequencer.appMovedToBackground()

        clock.minutes(29.99, after: start)
        sequencer.tick()
        #expect(recorder.isArmed)

        clock.minutes(IdleDisarm.limit / 60, after: start)
        sequencer.tick()
        #expect(!recorder.isArmed)
        #expect(sequencer.disarmedForIdle)
        #expect(sequencer.armedDevice == nil)
    }

    @Test("A Take never disarms, and counts as use: the 30 minutes start again after it")
    func takeResetsIdle() {
        let clock = TestClock(start)
        let (sequencer, recorder) = makeSequencer(now: { clock.date })
        sequencer.start()
        sequencer.appMovedToBackground()
        clock.minutes(10, after: start)
        sequencer.record(sources: [], allowance: nil)

        clock.minutes(45, after: start)
        sequencer.tick()
        #expect(recorder.isRecording)
        sequencer.stop()

        clock.minutes(74, after: start)
        sequencer.tick()
        #expect(recorder.isArmed)

        clock.minutes(75, after: start)
        sequencer.tick()
        #expect(!recorder.isArmed)
    }

    @Test("Coming back to the app after an idle disarm Arms again")
    func comingBackArmsAgain() {
        let clock = TestClock(start)
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source, now: { clock.date })
        sequencer.start()
        sequencer.appMovedToBackground()
        clock.minutes(30, after: start)
        sequencer.tick()

        sequencer.appBecameActive()

        #expect(recorder.isArmed)
        #expect(!sequencer.disarmedForIdle)
        #expect(source.opened.count == 2)
    }

    @Test("Arm again from the alert Arms and clears the idle disarm, without starting a Take")
    func armAgain() {
        let clock = TestClock(start)
        let (sequencer, recorder) = makeSequencer(now: { clock.date })
        sequencer.start()
        sequencer.appMovedToBackground()
        clock.minutes(30, after: start)
        sequencer.tick()

        sequencer.armAgain()

        #expect(recorder.isArmed)
        #expect(!recorder.isRecording)
        #expect(!sequencer.disarmedForIdle)
    }

    @Test("An idle disarm tells the events stream why")
    func idleEvent() async {
        let clock = TestClock(start)
        let (sequencer, _) = makeSequencer(now: { clock.date })
        sequencer.start()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        sequencer.appMovedToBackground()
        clock.minutes(30, after: start)

        sequencer.tick()

        #expect(await events.next() == .disarmed(reason: .idle))
    }

    @Test("Take 01 of a new Show is told too, though it ends like Take 01 of the last one")
    func sameTakeNumberInANewShow() async throws {
        let (sequencer, recorder) = makeSequencer()
        sequencer.start()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        sequencer.record(sources: [], allowance: nil)
        sequencer.stop()
        try recorder.endShow()

        sequencer.record(sources: [], allowance: nil)
        sequencer.stop()
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
        sequencer.arm()
        for _ in 0..<20 {
            sequencer.record(sources: [], allowance: nil)
            sequencer.stop()
        }
        var events = sequencer.events.makeAsyncIterator()

        // 41 events were told; only the newest 32 are kept, so the .armed at the start is gone.
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
        _ = await events.next()  // .armed
        sequencer.record(sources: [], allowance: nil)
        _ = await events.next()  // .takeStarted

        try recorder.restartInput(on: FakeAudioDevice(inputChannelCount: 2))
        #expect(sequencer.takeStartedAt == nil)
        sequencer.screenDisappeared()

        #expect(await told(&events, through: .disarmed(reason: .screenGone)) == [
            .takeEnded(TakeEnd(take: 1, reason: .inputChanged)), .disarmed(reason: .screenGone),
        ])
    }

    @Test("A Take started elsewhere that starts and ends between two ticks is still told, start then end")
    func takeBetweenTicks() async throws {
        let (sequencer, recorder) = makeSequencer()
        sequencer.start()
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed

        try recorder.startTake()
        try recorder.stopTake()
        sequencer.tick()
        sequencer.screenDisappeared()

        #expect(await told(&events, through: .disarmed(reason: .screenGone)) == [
            .takeStarted(take: 1), .takeEnded(TakeEnd(take: 1, reason: .stopped)), .disarmed(reason: .screenGone),
        ])
    }

    // MARK: - Interruptions

    @Test("An interruption during a Take stops input; when it ends, input restarts on the same device and the Take goes on")
    func interruptionDuringATake() throws {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source)
        sequencer.start()
        let device = try #require(source.opened.last)
        sequencer.record(sources: [], allowance: nil)

        sequencer.handle(.interruptionBegan)
        device.stop()  // The system stops input.
        sequencer.handle(.interruptionEnded(shouldResume: true))

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

        sequencer.handle(.interruptionBegan)
        device.stop()
        sequencer.handle(.interruptionEnded(shouldResume: true))

        sequencer.stop()

        let told = await told(&events, through: .takeEnded(TakeEnd(take: 1, reason: .stopped)))
        #expect(told.filter { $0 == .inputStopped }.count == 1)
        #expect(told.filter { $0 == .inputRestarted }.count == 1)
    }

    @Test("Starting a Take clears an interruption's old notice")
    func recordClearsTheNotice() throws {
        let source = FakeInputDevices()
        let (sequencer, _) = makeSequencer(source)
        sequencer.start()
        let device = try #require(source.opened.last)
        sequencer.record(sources: [], allowance: nil)
        sequencer.handle(.interruptionBegan)
        device.stop()
        sequencer.handle(.interruptionEnded(shouldResume: true))
        sequencer.stop()
        #expect(sequencer.interruptions.notice != nil)

        sequencer.record(sources: [], allowance: nil)

        #expect(sequencer.interruptions.notice == nil)
    }

    @Test("A new iOS route re-Arms between Takes and moves a running Take")
    func routeChangeAction() {
        let (sequencer, _) = makeSequencer()
        sequencer.start()
        #expect(sequencer.routeChanged() == .rearm)
        sequencer.record(sources: [], allowance: nil)
        #expect(sequencer.routeChanged() == .moveInput)
    }

    @Test("A restart that fails leaves input stopped and says so in the notice")
    func failedRestart() {
        let (sequencer, _) = makeSequencer()  // Nothing Armed, so there's nothing to restart.

        sequencer.handle(.interruptionBegan)
        sequencer.handle(.interruptionEnded(shouldResume: true))

        #expect(sequencer.interruptions.isInputStopped)
        #expect(sequencer.interruptions.notice?.hasPrefix("Couldn't restart audio input: ") == true)
    }

    @Test("A media reset during a Take opens the interface again at the Take's rate, uncapped, and the Take goes on when the format matches")
    func mediaResetSameFormat() throws {
        let source = FakeInputDevices()
        let (sequencer, recorder) = makeSequencer(source, capsAt48k: true)
        sequencer.start()
        sequencer.record(sources: [], allowance: nil)
        var heard: [String?] = []
        sequencer.didArm = { device in heard.append(device?.name) }

        sequencer.handle(.mediaServicesReset)

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

        sequencer.handle(.mediaServicesReset)

        #expect(!recorder.isRecording)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .inputChanged))
        #expect(recorder.isArmed)
        #expect(recorder.usbChannelCount == 2)
        #expect(sequencer.interruptions.notice == "The system reset its audio and the input changed, so the Take ended and was saved. Press record to start the next Take.")
        #expect(sequencer.recordError == nil)
    }
}

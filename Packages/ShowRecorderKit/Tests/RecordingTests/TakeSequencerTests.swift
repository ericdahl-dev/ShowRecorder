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
                let device = FakeAudioDevice(name: id, inputChannelCount: channels)
                opened.append(device)
                return device
            })
    }

    func devices() -> [DeviceChoice] { choices }
}

@MainActor
@Suite("Take sequencer")
struct TakeSequencerTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "TakeSequencerTests-\(UUID().uuidString)")

    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func makeSequencer(_ source: FakeInputDevices = FakeInputDevices(), capsAt48k: Bool = false, now: @escaping () -> Date = Date.init) -> (TakeSequencer, Recorder) {
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        return (TakeSequencer(recorder: recorder, devices: source, capsAt48k: { capsAt48k }, now: now), recorder)
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

    @Test("A Take the recorder ends on its own is told on the next tick, and its start time cleared")
    func takeEndedOnItsOwn() async throws {
        let (sequencer, recorder) = makeSequencer()
        sequencer.arm()
        sequencer.record(sources: [], allowance: nil)
        var events = sequencer.events.makeAsyncIterator()
        _ = await events.next()  // .armed
        _ = await events.next()  // .takeStarted

        try recorder.restartInput(on: FakeAudioDevice(inputChannelCount: 2))
        sequencer.tick()

        #expect(await events.next() == .takeEnded(TakeEnd(take: 1, reason: .inputChanged)))
        #expect(sequencer.takeStartedAt == nil)
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
}

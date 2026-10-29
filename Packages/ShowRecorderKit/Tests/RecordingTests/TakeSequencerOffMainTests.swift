import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

/// Record without the main actor waiting on the Drive (#914): the sequencer starts the Take through
/// `Recorder.startTakeOffMain`, and a Stop that comes while it is starting cancels the start.
@MainActor
@Suite("Take sequencer: starting a Take off the main actor", .timeLimit(.minutes(5)))
struct TakeSequencerOffMainTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "TakeSequencerOffMainTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    /// How often the Drive was asked for, and a gate its answer can wait on.
    final class Asks: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        let gate = TestGate()
        var holds = false
        func ask() { lock.withLock { count += 1 } }
        var calls: Int { lock.withLock { count } }
    }

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func makeSequencer(_ asks: Asks) -> (TakeSequencer, Recorder) {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: {
                asks.ask()
                if asks.holds { asks.gate.wait() }
                return DriveAccess(folder: drive)
            }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300))
        return (TakeSequencer(recorder: recorder, devices: FakeInputDevices(), capsAt48k: { false }), recorder)
    }

    func waitForTheDrive(_ asks: Asks) async {
        let deadline = ContinuousClock.now + .seconds(60)
        while asks.calls == 0, ContinuousClock.now < deadline { await Task.yield() }
    }

    @Test("Recording off the main actor starts the Take, tells it, and stamps its start")
    func startsATake() async {
        let (sequencer, recorder) = makeSequencer(Asks())
        sequencer.getReady()
        var events = sequencer.events.makeAsyncIterator()

        let started = await sequencer.recordOffMain(sources: [], allowance: nil)

        #expect(started)
        #expect(recorder.isRecording)
        #expect(sequencer.takeStartedAt != nil)
        #expect(sequencer.recordError == nil)
        #expect(await events.next(isolation: #isolation) == .ready(sequencer.readyDevice!))
        #expect(await events.next(isolation: #isolation) == .takeStarted(take: 1))
        await sequencer.stop()
    }

    @Test("A Stop that comes while the Take is starting cancels the start: no Take, no error, nothing left")
    func stopCancelsTheStart() async throws {
        let asks = Asks()
        asks.holds = true
        defer { asks.gate.open() }
        let (sequencer, recorder) = makeSequencer(asks)
        sequencer.getReady()

        let starting = Task { @MainActor in await sequencer.recordOffMain(sources: [], allowance: nil) }
        await waitForTheDrive(asks)
        #expect(recorder.isStarting)
        await sequencer.stop()
        asks.gate.open()

        #expect(await starting.value == false)
        #expect(!recorder.isRecording)
        #expect(!recorder.isStarting)
        #expect(sequencer.takeStartedAt == nil)
        #expect(sequencer.recordError == nil, "a canceled start is not an error")
        let show = try #require(recorder.currentShow).name
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: "\(show)/Take 01").path))
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/Take 01").path))
        #expect(recorder.currentShow?.takeCount == 0, "the Take number was given back")
        #expect(ShowFile.read(from: try #require(recorder.currentShow).folder)?.takes == nil, "on disk too")
        // The next press works, and is Take 01.
        var events = sequencer.events.makeAsyncIterator()
        #expect(await sequencer.recordOffMain(sources: [], allowance: nil))
        _ = await events.next(isolation: #isolation)
        #expect(await events.next(isolation: #isolation) == .takeStarted(take: 1))
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "\(show)/Take 01").path))
        await sequencer.stop()
    }

    @Test("A second press while one is starting changes nothing")
    func secondPressIgnored() async {
        let asks = Asks()
        asks.holds = true
        defer { asks.gate.open() }
        let (sequencer, recorder) = makeSequencer(asks)
        sequencer.getReady()

        let starting = Task { @MainActor in await sequencer.recordOffMain(sources: [], allowance: nil) }
        await waitForTheDrive(asks)
        let second = await sequencer.recordOffMain(sources: [], allowance: nil)
        asks.gate.open()

        #expect(second == false)
        #expect(await starting.value)
        #expect(recorder.isRecording)
        #expect(asks.calls == 1, "the Drive was asked for once")
        await sequencer.stop()
    }

    @Test("A start that fails says why, as record does")
    func failureSaysWhy() async {
        let (sequencer, recorder) = makeSequencer(Asks())

        let started = await sequencer.recordOffMain(sources: [], allowance: nil)

        #expect(!started)
        #expect(!recorder.isRecording)
        #expect(sequencer.recordError?.hasPrefix("Couldn't start recording: ") == true)
    }
}

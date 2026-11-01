import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// With the rule on, Stop writes the last Take's Copies off the main actor (#652, A3b): the main actor stays free while a
/// writer is blocked, and the result is the one Stop gives inline.
@MainActor
@Suite("Async Stop off the main actor")
struct AsyncStopOffMainTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "AsyncStopOffMainTests-\(UUID().uuidString)")
    let show = "2026-10-06 Show"

    /// A Stem whose finalize waits on the gate (bounded by `hangGuard`), and says it got there.
    final class GatedStem: StemSink, @unchecked Sendable {
        let inner: StemWriter
        let gate: TestGate
        private let lock = NSLock()
        private var enteredFlag = false
        init(_ inner: StemWriter, gate: TestGate) { self.inner = inner; self.gate = gate }
        var entered: Bool { lock.withLock { enteredFlag } }
        var frameCount: UInt64 { inner.frameCount }
        func append(_ samples: UnsafeBufferPointer<Float>) throws { try inner.append(samples) }
        func commitHeader() throws { try inner.commitHeader() }
        func finalize() throws {
            lock.withLock { enteredFlag = true }
            gate.wait()
            try inner.finalize()
        }
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try inner.setMarkers(markers) }
    }

    /// Records one Take of 4 800 frames and stops it, with the Device Stem gated when `gate` is given.
    private func makeRecorder(
        in folder: URL, asyncStop: Bool, gate: TestGate? = nil, stem: @escaping (GatedStem) -> Void = { _ in },
        drive: URL? = nil, driveIsUp: @escaping @Sendable () -> Bool = { false }, checkInterval: Duration? = nil
    ) -> Recorder {
        Recorder(
            deviceFolder: folder.appending(path: "Device"),
            driveFolder: { driveIsUp() ? drive.map { DriveAccess(folder: $0) } : nil },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                guard let gate, url.path.hasPrefix(folder.appending(path: "Device").path) else { return writer }
                let gated = GatedStem(writer, gate: gate)
                stem(gated)
                return gated
            },
            destinationCheckInterval: checkInterval, writerStopTimeout: .seconds(60), asyncStopAvailable: { asyncStop })
    }

    @Test("With the rule on, the main actor is free while a writer is blocked; the result equals the inline result")
    func mainActorFreeAndSameResult() async throws {
        // Inline reference, rule off.
        let inlineRoot = root.appending(path: "inline")
        let inline = makeRecorder(in: inlineRoot, asyncStop: false)
        let inlineAudio = FakeAudioDevice(inputChannelCount: 1)
        try inline.getReady(inlineAudio)
        try inline.startTake()
        inlineAudio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await inline.stopTake()

        // Async, with the Device Stem blocked in finalize.
        let asyncRoot = root.appending(path: "async")
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: asyncRoot, asyncStop: true, gate: gate, stem: { gated = $0 })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])

        let stop = Task { @MainActor in try await recorder.stopTake() }
        try await waitUntil { recorder.isFinishing }
        try await waitUntil { gated?.entered == true }

        // The finish is blocked in a writer, and this body (the main actor) still runs.
        #expect(recorder.isFinishing)
        #expect(!recorder.isRecording)
        #expect(recorder.session == nil, "the session is unreachable from the Recorder between the snapshot and the write-back")
        #expect(recorder.lastTakeEnd == nil, "nothing is published until the finish is done")
        #expect(throws: RecorderError.finishing) { try recorder.startTake() }
        #expect(!recorder.isRecording)
        // A second Stop waits for the first one's publish and does not finish a second time.
        nonisolated(unsafe) var secondReturned = false
        let second = Task { @MainActor in
            try await recorder.stopTake()
            secondReturned = true
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!secondReturned, "a second Stop returned while the first was still saving")
        #expect(recorder.isFinishing)

        gate.open()
        try await stop.value
        try await second.value
        #expect(secondReturned)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped), "the second Stop returned before the publish")
        #expect(!recorder.isFinishing)

        let name = "\(show)/Take 01"
        let inlineJSON = try Data(contentsOf: inlineRoot.appending(path: "Device/\(name)/Take.json"))
        let asyncJSON = try Data(contentsOf: asyncRoot.appending(path: "Device/\(name)/Take.json"))
        #expect(asyncJSON == inlineJSON)
        let stem = asyncRoot.appending(path: "Device/\(name)/01 USB 01.wav")
        #expect(try StemFile.inspect(stem).frameCount == 4_800)
        #expect(recorder.copies[.device] == inline.copies[.device])
        // The next Take starts once Stop is done.
        try recorder.startTake()
        #expect(recorder.isRecording)
        gate.open()
        try await recorder.stopTake()
    }

    @Test("A Drive that appears after the snapshot is not added: no check reaches the dropped session, no Copy appears")
    func lateDriveIsIgnored() async throws {
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        nonisolated(unsafe) var driveUp = false
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(
            in: root, asyncStop: true, gate: gate, stem: { gated = $0 }, drive: drive,
            driveIsUp: { driveUp }, checkInterval: .milliseconds(10))
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])

        let stop = Task { @MainActor in try await recorder.stopTake() }
        try await waitUntil { gated?.entered == true }
        driveUp = true
        await recorder.checkDestinations()
        // The periodic check was canceled by the stop; give it many intervals to prove it.
        try await Task.sleep(for: .milliseconds(150))
        #expect(recorder.session == nil)
        gate.open()
        try await stop.value

        #expect(recorder.copies[.drive] == .missing)
        let driveTake = drive.appending(path: "\(show)/Take 01")
        #expect(!FileManager.default.fileExists(atPath: driveTake.path), "a Drive Copy was started after the snapshot")
        let metadata = try TakeMetadata.read(fromTakeFolder: root.appending(path: "Device/\(show)/Take 01"))
        #expect(metadata.standIns == nil)
        #expect(metadata.gaps.isEmpty)
    }

    @Test("Canceling the caller of Stop doesn't skip the finish or the publish, and the flag is reset")
    func cancelingTheCaller() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])

        let stop = Task { @MainActor in try await recorder.stopTake() }
        try await waitUntil { gated?.entered == true }
        stop.cancel()
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.isFinishing, "canceling the caller ended the finishing state early")
        gate.open()
        try await stop.value

        #expect(!recorder.isFinishing)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped))
        let stem = root.appending(path: "Device/\(show)/Take 01/01 USB 01.wav")
        #expect(try StemFile.inspect(stem).frameCount == 4_800)
    }

    @Test("While Finishing: getReady throws .finishing, standDown still stops the device, and the error says why")
    func getReadyAndStandDownWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])

        let stop = Task { @MainActor in try await recorder.stopTake() }
        try await waitUntil { gated?.entered == true }
        #expect(throws: RecorderError.finishing) { try recorder.getReady(FakeAudioDevice(inputChannelCount: 1)) }
        #expect(recorder.isReady, "a refused get-ready leaves the Ready device alone")
        #expect(RecorderError.finishing.errorDescription == "The last Take is still being saved.")
        recorder.standDown()
        #expect(!recorder.isReady)
        gate.open()
        try await stop.value

        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped))
        let stem = root.appending(path: "Device/\(show)/Take 01/01 USB 01.wav")
        #expect(try StemFile.inspect(stem).frameCount == 4_800)
    }

    @Test("While Finishing, the Show can't be changed under the Take being saved, and waitForRepair waits for the publish")
    func showChangesAndWaitWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])

        let stop = Task { @MainActor in try await recorder.stopTake() }
        try await waitUntil { gated?.entered == true }
        #expect(throws: RecorderError.finishing) { try recorder.startNewShow(name: "Other", venue: "") }
        #expect(throws: RecorderError.finishing) { try recorder.endShow() }
        #expect(!recorder.prepareNextShow(from: Template(name: "T", venue: nil, channelNames: [:], mixerNetworkName: nil, mixerAddress: "", preRollSeconds: 0)))
        nonisolated(unsafe) var published: TakeEnd?
        let waiter = Task { @MainActor in
            await recorder.waitForRepair()
            published = recorder.lastTakeEnd
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(published == nil, "waitForRepair returned before the Take was published")
        gate.open()
        try await stop.value
        await waiter.value
        #expect(published == TakeEnd(take: 1, reason: .stopped))
        #expect(recorder.currentShow?.takeCount == 1)
    }

    /// Starts a Take on `recorder` and a Stop of it that is blocked in the gated Device Stem.
    private func startBlockedStop(
        _ recorder: Recorder, audio: FakeAudioDevice, gated: @escaping () -> GatedStem?
    ) async throws -> Task<Void, any Error> {
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        let stop = Task { @MainActor in try await recorder.stopTake() }
        try await waitUntil { gated()?.entered == true }
        return stop
    }

    @Test("A Drive that is up before Stop does join the Take (the control for the late-Drive test)")
    func driveUpBeforeStopJoins() async throws {
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        nonisolated(unsafe) var driveUp = false
        let recorder = makeRecorder(in: root, asyncStop: true, drive: drive, driveIsUp: { driveUp })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        driveUp = true
        await recorder.checkDestinations()
        try await recorder.stopTake()
        #expect(recorder.copies[.drive] != .missing)
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/Take 01").path))
    }

    @Test("Quit and window close ask to stop while the Take is being saved, and a Stop from there waits for the save")
    func quitWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let source = FakeInputDevices([("xr18", 1)])
        let sequencer = TakeSequencer(recorder: recorder, devices: source, capsAt48k: { false })
        sequencer.getReady()
        let audio = try #require(source.opened.last)
        let stop = try await startBlockedStop(recorder, audio: audio, gated: { gated })
        #expect(sequencer.quitRequested() == .askToStop)
        #expect(sequencer.windowCloseRequested() == .askToStop)
        // The operator answers "stop": the sequencer's Stop returns only once the Take is published.
        nonisolated(unsafe) var returned = false
        let answered = Task { @MainActor in
            await sequencer.stop()
            returned = true
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!returned)
        gate.open()
        try await stop.value
        await answered.value
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped))
        #expect(sequencer.quitRequested() == .quit)
    }

    @Test("The Take's start time stays until the save is published, so the screen can freeze the timer and keep the Live Activity")
    func startTimeKeptWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let source = FakeInputDevices([("xr18", 1)])
        let sequencer = TakeSequencer(recorder: recorder, devices: source, capsAt48k: { false })
        sequencer.getReady()
        let audio = try #require(source.opened.last)
        #expect(sequencer.record(sources: [], allowance: nil))
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        #expect(sequencer.takeStartedAt != nil)
        let stopping = Task { @MainActor in await sequencer.stop() }
        try await waitUntil { gated?.entered == true }
        #expect(recorder.isFinishing)
        sequencer.tick()
        #expect(sequencer.takeStartedAt != nil)
        gate.open()
        await stopping.value
        #expect(!recorder.isFinishing)
        #expect(sequencer.takeStartedAt == nil)
    }

    @Test("A gain change made while the Take is being saved is kept on the Show, not overwritten by the publish")
    func gainChangeWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        let stop = try await startBlockedStop(recorder, audio: audio, gated: { gated })
        recorder.logGainChange(TakeMetadata.GainChange(usbChannel: 1, channel: 1, headamp: 1, fromGainDb: 14.5, toGainDb: 11.5, reason: .clipProtection, compensations: []))
        gate.open()
        try await stop.value
        #expect(recorder.currentShow?.gainChanges.count == 1)
    }

    @Test("A name typed after Stop was pressed is for the next Take: the saved Take's files keep their names")
    func nameTypedWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        let stop = try await startBlockedStop(recorder, audio: audio, gated: { gated })
        #expect(recorder.setChannelName("Late", forChannel: 1))
        gate.open()
        try await stop.value
        await recorder.waitForRepair()
        let folder = root.appending(path: "Device/\(show)/Take 01")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains("01 USB 01.wav"), "the new name reached the Take that had just ended: \(names)")
    }

    @Test("While the Take is being saved, deletes and direct moves are refused, and Marker renames wait for the save")
    func editsWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 }, drive: drive, driveIsUp: { true })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        let stop = try await startBlockedStop(recorder, audio: audio, gated: { gated })
        let deleted = [
            recorder.deleteShow(named: "Other", from: [.device]),
            recorder.deleteTake(1, ofShow: "Other", from: [.device]),
            recorder.deleteChannel(1, inTake: 1, ofShow: "Other", from: [.device]),
        ]
        for outcome in deleted {
            #expect(outcome.deleted.isEmpty)
            #expect(outcome.failed.map(\.reason) == ["The last Take is still being saved."])
        }
        #expect(await recorder.moveDriveOnlyTakes().isEmpty)
        nonisolated(unsafe) var renamedAfterPublish: Bool?
        let rename = Task { @MainActor in
            _ = await recorder.renameLastTakeMarker(at: 0, to: "x")
            renamedAfterPublish = recorder.lastTakeEnd != nil
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(renamedAfterPublish == nil)
        gate.open()
        try await stop.value
        await rename.value
        #expect(renamedAfterPublish == true)
    }

    @Test("A refused get-ready while the Take is being saved leaves the sequencer's Ready device alone; a route move waits for the save")
    func sequencerGetReadyWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let source = FakeInputDevices([("xr18", 1)])
        let sequencer = TakeSequencer(recorder: recorder, devices: source, capsAt48k: { false })
        sequencer.getReady()
        let ready = sequencer.readyDevice
        #expect(ready != nil)
        let audio = try #require(source.opened.last)
        let stop = try await startBlockedStop(recorder, audio: audio, gated: { gated })
        sequencer.getReady()
        #expect(recorder.isReady)
        #expect(sequencer.readyDevice?.id == ready?.id, "the sequencer forgot a device the recorder still has")
        gate.open()
        try await stop.value
    }

    @Test("A mismatched replacement device waits for the save before it gets ready")
    func restartInputWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        let stop = try await startBlockedStop(recorder, audio: audio, gated: { gated })
        nonisolated(unsafe) var continued: Bool?
        let move = Task { @MainActor in continued = try await recorder.restartInput(on: FakeAudioDevice(inputChannelCount: 2)) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(continued == nil)
        gate.open()
        try await stop.value
        try await move.value
        #expect(continued == false)
        #expect(recorder.usbChannelCount == 2)
    }

    @Test("A device list change while the Take is being saved waits for the save, then gets ready on the new format")
    func deviceListChangedWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let source = FakeInputDevices([("xr18", 1)])
        let sequencer = TakeSequencer(recorder: recorder, devices: source, capsAt48k: { false })
        sequencer.getReady()
        let audio = try #require(source.opened.last)
        let stop = try await startBlockedStop(recorder, audio: audio, gated: { gated })
        source.choices = [source.choice(id: "xr18", channels: 2)]
        nonisolated(unsafe) var returned = false
        let change = Task { @MainActor in
            await sequencer.deviceListChanged()
            returned = true
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!returned)
        gate.open()
        try await stop.value
        await change.value
        #expect(recorder.isReady)
        #expect(recorder.usbChannelCount == 2, "the recorder kept the old format")
    }

    @Test("A tier change while the Take is being saved shows no error, and the input gets ready again at the new rate once the save ends (#884)")
    func tierChangedWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let source = FakeInputDevices([("xr18", 1)])
        source.rates["xr18"] = 96_000
        nonisolated(unsafe) var capped = false
        let sequencer = TakeSequencer(recorder: recorder, devices: source, capsAt48k: { capped })
        sequencer.getReady()
        #expect(recorder.sampleRate == 96_000)
        let audio = try #require(source.opened.last)
        let stop = try await startBlockedStop(recorder, audio: audio, gated: { gated })

        capped = true   // a refund, say, while the Take is on its way to disk
        sequencer.tierChanged()
        #expect(sequencer.getReadyError == nil, "no false \"Couldn't start\" after a clean Take: \(sequencer.getReadyError ?? "")")
        gate.open()
        try await stop.value

        try await waitUntil { recorder.sampleRate == 48_000 }
        #expect(sequencer.getReadyError == nil)
    }

    @Test("Pre-roll or sample rate changes while the Take is being saved show no error, and the input gets ready again once after the save (#932)")
    func settingsChangedWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let source = FakeInputDevices([("xr18", 1)])
        let sequencer = TakeSequencer(recorder: recorder, devices: source, capsAt48k: { false })
        sequencer.getReady()
        let audio = try #require(source.opened.last)
        let getsReadyBefore = source.opened.count
        let stop = try await startBlockedStop(recorder, audio: audio, gated: { gated })

        sequencer.settingsChanged()
        sequencer.settingsChanged()
        sequencer.settingsChanged()
        #expect(sequencer.getReadyError == nil, "no false \"Couldn't start\" after a clean Take: \(sequencer.getReadyError ?? "")")
        gate.open()
        try await stop.value

        try await waitUntil { source.opened.count > getsReadyBefore }
        try await Task.sleep(for: .milliseconds(200))
        #expect(sequencer.getReadyError == nil)
        #expect(source.opened.count == getsReadyBefore + 1, "three changes, one get-ready")
        #expect(recorder.isReady)
    }

    @Test("A gain change buffered during the save doesn't write the Show.json of a Drive Stop gave up on")
    func gainChangeSkipsAbandonedDrive() async throws {
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let driveGate = TestGate()
        defer { driveGate.open() }
        let recorder = Recorder(
            deviceFolder: root.appending(path: "Device"), driveFolder: { DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                return url.path.hasPrefix(drive.path) ? StopNeverBlocksTests.HangingStem(writer, gate: driveGate) : writer
            },
            destinationCheckInterval: nil, writerStopTimeout: .milliseconds(500), asyncStopAvailable: { true })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await Task.sleep(for: .milliseconds(100))
        let showFile = drive.appending(path: "\(show)/Show.json")
        let before = try Data(contentsOf: showFile)

        let stop = Task { @MainActor in try await recorder.stopTake() }
        try await waitUntil { recorder.isFinishing }
        recorder.logGainChange(TakeMetadata.GainChange(usbChannel: 1, channel: 1, headamp: 1, fromGainDb: 14.5, toGainDb: 11.5, reason: .clipProtection, compensations: []))
        try await stop.value
        #expect(recorder.copies[.drive] == .hasGaps, "the Drive wasn't given up on, so the test proves nothing")
        #expect(recorder.currentShow?.gainChanges.count == 1)
        #expect(try Data(contentsOf: showFile) == before, "the replay wrote the abandoned Drive's Show.json")
        driveGate.open()
        await recorder.waitForRepair()
    }

    @Test("With the rule off, Stop doesn't suspend: the Take is published when the call returns")
    func ruleOffIsInline() async throws {
        let recorder = makeRecorder(in: root, asyncStop: false)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])

        let stop = Task { @MainActor in try await recorder.stopTake() }
        // Had Stop suspended, this body would run in between with the flag still true.
        var seenFinishing = false
        await Task.yield()
        seenFinishing = recorder.isFinishing
        #expect(!seenFinishing)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped))
        try await stop.value
        #expect(!recorder.isFinishing)
    }
}

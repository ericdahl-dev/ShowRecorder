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
        drive: URL? = nil, driveIsUp: @escaping () -> Bool = { false }, checkInterval: Duration? = nil
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
            destinationCheckInterval: checkInterval, writerStopTimeout: .seconds(60), asyncStopAvailable: asyncStop)
    }

    @Test("With the rule on, the main actor is free while a writer is blocked; the result equals the inline result")
    func mainActorFreeAndSameResult() async throws {
        // Inline reference, rule off.
        let inlineRoot = root.appending(path: "inline")
        let inline = makeRecorder(in: inlineRoot, asyncStop: false)
        let inlineAudio = FakeAudioDevice(inputChannelCount: 1)
        try inline.arm(inlineAudio)
        try inline.startTake()
        inlineAudio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await inline.stopTake()

        // Async, with the Device Stem blocked in finalize.
        let asyncRoot = root.appending(path: "async")
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: asyncRoot, asyncStop: true, gate: gate, stem: { gated = $0 })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
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
        // A second Stop returns at once: it neither waits on the first nor finishes a second time.
        try await recorder.stopTake()
        #expect(recorder.isFinishing)

        gate.open()
        try await stop.value
        #expect(!recorder.isFinishing)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped))

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
        try recorder.arm(audio)
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
        try recorder.arm(audio)
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

    @Test("While Finishing: arm throws .finishing, disarm still stops the device, and the error says why")
    func armAndDisarmWhileFinishing() async throws {
        let gate = TestGate()
        nonisolated(unsafe) var gated: GatedStem?
        let recorder = makeRecorder(in: root, asyncStop: true, gate: gate, stem: { gated = $0 })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])

        let stop = Task { @MainActor in try await recorder.stopTake() }
        try await waitUntil { gated?.entered == true }
        #expect(throws: RecorderError.finishing) { try recorder.arm(FakeAudioDevice(inputChannelCount: 1)) }
        #expect(recorder.isArmed, "a refused Arm leaves the Armed device alone")
        #expect(RecorderError.finishing.errorDescription == "The last Take is still being saved.")
        recorder.disarm()
        #expect(!recorder.isArmed)
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
        try recorder.arm(audio)
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

    @Test("With the rule off, Stop doesn't suspend: the Take is published when the call returns")
    func ruleOffIsInline() async throws {
        let recorder = makeRecorder(in: root, asyncStop: false)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
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

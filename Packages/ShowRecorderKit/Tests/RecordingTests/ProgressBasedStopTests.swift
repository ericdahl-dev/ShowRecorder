import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// With the asynchronous Stop on, a Drive that is slow but still writing is waited for, and only one that has stopped
/// making progress is abandoned (#817). With it off, Stop keeps its fixed deadline.
@MainActor
@Suite("Progress-based Stop")
struct ProgressBasedStopTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ProgressBasedStopTests-\(UUID().uuidString)")
    let show = "2026-10-06 Show"

    init() { try? FileManager.default.removeItem(at: root) }

    /// A Drive Stem: its first write waits on the gate; every write after takes `delay` seconds (set by the test).
    final class SlowStem: StemSink, @unchecked Sendable {
        let inner: StemWriter
        let gate: TestGate
        private let lock = NSLock()
        private var delay: TimeInterval = 0
        /// How long each finalize takes.
        let finalizeDelay: TimeInterval
        private var first = true
        init(_ inner: StemWriter, gate: TestGate, finalizeDelay: TimeInterval = 0) {
            self.inner = inner
            self.gate = gate
            self.finalizeDelay = finalizeDelay
        }
        func setDelay(_ seconds: TimeInterval) { lock.withLock { delay = seconds } }
        var frameCount: UInt64 { inner.frameCount }
        func append(_ samples: UnsafeBufferPointer<Float>) throws {
            if lock.withLock({ defer { first = false }; return first }) { gate.wait() }
            let wait = lock.withLock { delay }
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            try inner.append(samples)
        }
        func commitHeader() throws { try inner.commitHeader() }
        func finalize() throws {
            if finalizeDelay > 0 { Thread.sleep(forTimeInterval: finalizeDelay) }
            try inner.finalize()
        }
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try inner.setMarkers(markers) }
    }

    /// A Take of 96,000 frames that piles up behind a held first write on the Drive, then a Stop; the Drive then writes
    /// every chunk in 100 ms. Draining takes about 2.4 s, longer than the 2 s Stop timeout, with progress throughout.
    private func slowDriveStop(asyncStop: Bool) async throws -> Recorder {
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let gate = TestGate()
        nonisolated(unsafe) var slow: SlowStem?
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                guard url.path.hasPrefix(drive.path) else { return writer }
                let stem = SlowStem(writer, gate: gate)
                slow = stem
                return stem
            },
            destinationCheckInterval: nil, writerStopTimeout: .seconds(2), asyncStopAvailable: asyncStop)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        for _ in 0..<20 { audio.deliver([Array(repeating: 0.25, count: 4_800)]) }
        // The gate opens from another thread: a busy main actor (other suites) must not hold it past the Stop timeout.
        nonisolated(unsafe) let held = slow
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            held?.setDelay(0.1)
            gate.open()
        }
        try await recorder.stopTake()
        return recorder
    }

    @Test("A Drive that is slow but still writing is waited for: its Stems are finalized and complete")
    func slowDriveIsWaitedFor() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try await slowDriveStop(asyncStop: true)
        #expect(recorder.copies[.drive] == .complete)
        let driveStem = root.appending(path: "Drive/\(show)/Take 01/01 USB 01.wav")
        #expect(try StemFile.inspect(driveStem).frameCount == 96_000)
    }

    @Test("While the Drive is being saved, the Recorder says how much audio it still has to write; afterwards it says nothing")
    func backlogIsReported() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let gate = TestGate()
        defer { gate.open() }
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                return url.path.hasPrefix(drive.path) ? SlowStem(writer, gate: gate) : writer
            },
            destinationCheckInterval: nil, writerStopTimeout: .seconds(10), asyncStopAvailable: true)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        // 2 s of audio, behind a Drive write that is held: nearly all of it is still waiting at Stop.
        for _ in 0..<20 { audio.deliver([Array(repeating: 0.25, count: 4_800)]) }
        let stopping = Task { @MainActor in try await recorder.stopTake() }
        try await waitUntil { (recorder.finishProgress?.driveBacklogSeconds ?? 0) > 1 }
        #expect(recorder.isFinishing)
        #expect(recorder.finishProgress?.isSavingToDrive == true)
        gate.open()
        try await stopping.value
        #expect(recorder.finishProgress == nil)
    }

    @Test("With the asynchronous Stop off, the same slow Drive is still abandoned at the fixed deadline")
    func ruleOffKeepsTheDeadline() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try await slowDriveStop(asyncStop: false)
        #expect(recorder.copies[.drive] == .hasGaps)
    }

    @Test("A Drive that makes no progress is still abandoned, with the rule on")
    func hungDriveIsAbandoned() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let gate = TestGate()
        defer { gate.open() }
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                return url.path.hasPrefix(drive.path) ? SlowStem(writer, gate: gate) : writer
            },
            destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300), asyncStopAvailable: true)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await Task.sleep(for: .milliseconds(100))
        try await recorder.stopTake()
        #expect(recorder.copies[.drive] == .hasGaps)
    }

    @Test("Finalizing counts as progress: three Stems that each take 150 ms to finalize are not abandoned at a 300 ms window")
    func slowFinalizeIsProgress() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let gate = TestGate()
        gate.open()
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                return url.path.hasPrefix(drive.path) ? SlowStem(writer, gate: gate, finalizeDelay: 0.15) : writer
            },
            destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300), asyncStopAvailable: true)
        let audio = FakeAudioDevice(inputChannelCount: 3)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver(Array(repeating: Array(repeating: Float(0.25), count: 4_800), count: 3))
        try await Task.sleep(for: .milliseconds(100))
        try await recorder.stopTake()
        #expect(recorder.copies[.drive] == .complete)
    }
}

import AudioIO
import Foundation
@testable import Recording
import Testing

/// A slow USB stick can block a free-space read for hundreds of milliseconds, and a running Take reads each Copy's free
/// space every second. On the main actor that stutters the screen (#814).
@MainActor
@Suite("Free space reads during a Take")
struct FreeSpaceOffMainTests {
    /// Counts which thread each free-space read ran on.
    final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var mainReads = 0
        private var otherReads = 0
        func read() {
            lock.withLock { if Thread.isMainThread { mainReads += 1 } else { otherReads += 1 } }
        }
        var counts: (main: Int, other: Int) { lock.withLock { (mainReads, otherReads) } }
    }

    /// Set once a read has begun, so a test can wait for that without a timer (a timer can starve behind blocked tests).
    final class Entered: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        private var onMain = false
        /// Notes that a read began, and on which thread.
        func set() { lock.withLock { value = true; onMain = Thread.isMainThread } }
        var isSet: Bool { lock.withLock { value } }
        var beganOnMain: Bool { lock.withLock { onMain } }
    }

    @Test("Checking a running Take's Destinations reads each Copy's free space off the main thread (#814)")
    func readsOffMain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FreeSpaceOffMainTests-\(UUID().uuidString)")
        let probe = Probe()
        let recorder = Recorder(
            deviceFolder: root, now: { RecordingTakeTests.showDay }, freeSpace: { _ in probe.read(); return .max },
            destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 480)])
        let before = probe.counts

        await recorder.checkDestinations()

        let after = probe.counts
        #expect(after.other > before.other, "the free space was read")
        #expect(after.main == before.main, "and not on the main thread")
        try await recorder.stopTake()
    }

    @Test("A free-space read that hangs holds no one up: the main actor stays free until it answers (#814)")
    func slowReadLeavesMainFree() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FreeSpaceOffMainTests-\(UUID().uuidString)")
        let gate = TestGate()
        let entered = Entered()
        defer { gate.open() }
        let recorder = Recorder(
            deviceFolder: root, now: { RecordingTakeTests.showDay }, freeSpace: { _ in entered.set(); gate.wait(); return .max },
            destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 480)])

        let checking = Task { @MainActor in await recorder.checkDestinations() }
        // Yield the main actor until the read has begun. Had the check run the read on main, this loop would sit behind
        // it until the gate's guard ends the wait. No clock here: the suite runs many tests on the main actor at once.
        for _ in 0..<100_000 where !entered.isSet { await Task.yield() }

        #expect(entered.isSet, "the read began")
        #expect(!entered.beganOnMain, "and not on the main thread, which stays free while it hangs")
        #expect(recorder.isRecording)
        gate.open()
        await checking.value
        try await recorder.stopTake()
    }

    @Test("Stop during a free-space read ends the check without touching the ended Take")
    func stopDuringTheRead() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "FreeSpaceOffMainTests-\(UUID().uuidString)")
        let gate = TestGate()
        let entered = Entered()
        defer { gate.open() }
        let recorder = Recorder(
            deviceFolder: root, now: { RecordingTakeTests.showDay }, freeSpace: { _ in entered.set(); gate.wait(); return 0 },
            destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 480)])

        let checking = Task { @MainActor in await recorder.checkDestinations() }
        for _ in 0..<100_000 where !entered.isSet { await Task.yield() }
        #expect(entered.isSet, "the read began")
        try await recorder.stopTake()
        gate.open()
        await checking.value

        // The reading said "no space", but it came after the Take had ended: it must not end anything else.
        #expect(!recorder.isRecording)
        #expect(recorder.lastTakeEnd?.reason == .stopped)
    }
}

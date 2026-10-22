import AudioIO
import Destinations
import Foundation
import Synchronization
@testable import Recording
import Testing

/// What Stop writes into the Show (Show.json, the report and the Reaper projects) is file work on a Drive that may be
/// slow, so with the asynchronous Stop it runs off the main thread (#652); the next Take can't start before it is done.
@MainActor
@Suite("Stop's file work off the main thread")
struct StopFileWorkOffMainTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "StopFileWorkOffMainTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    func recorder() throws -> (Recorder, FakeAudioDevice) {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
                                destinationCheckInterval: nil, asyncStopAvailable: { true })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        return (recorder, audio)
    }

    @Test("The Show's report and projects are rewritten off the main thread after Stop")
    func reportsOffMain() async throws {
        let (recorder, _) = try recorder()
        let threads = Mutex<[Bool]>([])
        recorder.reportWriter = { _, _, _ in threads.withLock { $0.append(Thread.isMainThread) } }

        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(!threads.withLock { $0 }.isEmpty, "the report was written")
        #expect(threads.withLock { $0 }.allSatisfy { !$0 }, "none of it on the main thread")
    }

    @Test("Show.json is rewritten for the Take's end off the main thread, before Stop is published")
    func showFileOffMain() async throws {
        let (recorder, _) = try recorder()
        let threads = Mutex<[Bool]>([])
        let real = recorder.finishShowFiles
        recorder.finishShowFiles = { show, names, date, skipped in
            threads.withLock { $0.append(Thread.isMainThread) }
            return real(show, names, date, skipped)
        }

        try await recorder.stopTake()

        #expect(threads.withLock { $0 } == [false])
        let file = try Data(contentsOf: device.appending(path: "2026-10-06 Show/Show.json"))
        #expect(String(decoding: file, as: UTF8.self).contains("lastTakeEndedAt"), "Show.json says when the Take ended")
        #expect(recorder.currentShow?.lastTakeEndedAt != nil)
    }

    @Test("A Take can't start while Stop is still writing the Show, and then starts on the finished Show.json")
    func nextTakeWaits() async throws {
        let (recorder, audio) = try recorder()
        let gate = DispatchSemaphore(value: 0)
        let entered = Mutex(false)
        let real = recorder.finishShowFiles
        recorder.finishShowFiles = { show, names, date, skipped in
            entered.withLock { $0 = true }
            _ = gate.wait(timeout: .now() + 60)
            return real(show, names, date, skipped)
        }

        let stopping = Task { try await recorder.stopTake() }
        try await waitUntil { entered.withLock { $0 } }
        #expect(recorder.isFinishing)
        #expect(throws: RecorderError.finishing) { try recorder.startTake() }
        gate.signal()
        try await stopping.value
        recorder.finishShowFiles = real

        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 480)])
        try await recorder.stopTake()
        #expect(recorder.currentShow?.takeCount == 2)
    }

    @Test("A name typed while Stop is finishing is still in the Show and in Show.json once it is published")
    func nameTypedWhileFinishing() async throws {
        let (recorder, _) = try recorder()
        let gate = DispatchSemaphore(value: 0)
        let entered = Mutex(false)
        let real = recorder.finishShowFiles
        recorder.finishShowFiles = { show, names, date, skipped in
            entered.withLock { $0 = true }
            _ = gate.wait(timeout: .now() + 60)
            return real(show, names, date, skipped)
        }
        defer { gate.signal() }

        let stopping = Task { try await recorder.stopTake() }
        try await waitUntil { entered.withLock { $0 } }
        recorder.setChannelName("Kick", forChannel: 1)
        gate.signal()
        try await stopping.value

        #expect(recorder.currentShow?.channelNames[1] == "Kick")
        let file = try Data(contentsOf: device.appending(path: "2026-10-06 Show/Show.json"))
        #expect(String(decoding: file, as: UTF8.self).contains("Kick"), "Show.json has the name")
    }
}

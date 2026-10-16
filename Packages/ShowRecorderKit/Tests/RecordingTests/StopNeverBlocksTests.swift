import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Stop never waits on a stuck Destination (#320).
@MainActor
@Suite("Stop never blocks")
struct StopNeverBlocksTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "StopNeverBlocksTests-\(UUID().uuidString)")
    let show = "2026-10-06 Show"

    typealias Gate = TestGate
    /// A Drive that hangs on a write (pulled mid-write, a dying stick) until the gate opens.
    final class HangingStem: StemSink, @unchecked Sendable {
        let inner: StemWriter
        let gate: Gate
        init(_ inner: StemWriter, gate: Gate) { self.inner = inner; self.gate = gate }
        var frameCount: UInt64 { inner.frameCount }
        func append(_ samples: UnsafeBufferPointer<Float>) throws { gate.wait(); try inner.append(samples) }
        func commitHeader() throws { try inner.commitHeader() }
        func finalize() throws { try inner.finalize() }
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try inner.setMarkers(markers) }
    }

    @Test("A Drive stuck on a write doesn't hold up Stop: the Take ends, the Device Copy is complete, the Drive Copy has Gaps and is never written again")
    func stuckDrive() async throws {
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let gate = Gate()
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                return url.path.hasPrefix(drive.path) ? HangingStem(writer, gate: gate) : writer
            },
            destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300))
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await Task.sleep(for: .milliseconds(100))

        let started = ContinuousClock.now
        try await recorder.stopTake()
        // Far below the gate's `hangGuard`. Stop returns to the main actor when its finish is done (#652), so under a parallel
        // run this also counts the wait for the other suites' main-actor work; a tight bound measured that, not the Drive.
        #expect(ContinuousClock.now - started < .seconds(30), "Stop waited on the stuck Drive")
        #expect(!recorder.isRecording)
        #expect(recorder.copies[.drive] == .hasGaps)
        let deviceStem = device.appending(path: "\(show)/Take 01/01 USB 01.wav")
        #expect(try StemFile.inspect(deviceStem).frameCount == 4_800)

        // The Drive wakes up later. The write it was stuck in can't be taken back, but the abandoned Copy starts no
        // new one: no header commit, no Markers, no finalize, so its declared length doesn't move.
        let driveStem = drive.appending(path: "\(show)/Take 01/01 USB 01.wav")
        let before = try StemFile.inspect(driveStem).frameCount
        gate.open()
        try await Task.sleep(for: .milliseconds(300))
        #expect(try StemFile.inspect(driveStem).frameCount == before)
        await recorder.waitForRepair()
        #expect(recorder.copies[.drive] == .hasGaps)
    }

    /// Stands in for writing a Take.json to a Copy Stop gave up on: notes whether each write ran on the main thread and
    /// whether the second started before the first returned. It holds the first one until `release()` (for at most
    /// `hangGuard`) and for at least 1 s, so a second write that doesn't wait for it has time to start.
    final class AbandonedWrites: @unchecked Sendable {
        private let lock = NSCondition()
        private var held = true
        private var onMain: [Bool] = []
        private var firstDone = false
        private var overlapped = false
        func write(_ metadata: TakeMetadata, to folder: URL) {
            lock.lock()
            onMain.append(Thread.isMainThread)
            let first = onMain.count == 1
            if first {
                let minimum = Date() + 1, deadline = Date() + TimeInterval(hangGuard.components.seconds)
                while held || Date() < minimum {
                    if !lock.wait(until: held ? deadline : minimum), held { break }
                }
            } else if onMain.count == 2 {
                overlapped = !firstDone
            }
            lock.unlock()
            try? metadata.write(to: folder)
            if first { lock.lock(); firstDone = true; lock.unlock() }
        }
        func release() { lock.lock(); held = false; lock.broadcast(); lock.unlock() }
        /// Whether each write so far ran on the main thread, in the order they started.
        var calls: [Bool] { lock.lock(); defer { lock.unlock() }; return onMain }
        /// Whether the second write started before the first had returned.
        var secondStartedEarly: Bool { lock.lock(); defer { lock.unlock() }; return overlapped }
    }

    /// A Recorder whose Drive Stems hang on `gate`, with one Take recorded and still running.
    private func recordingOnStuckDrive(
        gate: Gate, device: URL, drive: URL, freeSpace: @escaping (URL) -> Int64 = { DriveFolderStore.availableBytes(at: $0) },
        writeAbandoned: @escaping @Sendable (TakeMetadata, URL) -> Void = { try? $0.write(to: $1) }
    ) throws -> Recorder {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay }, freeSpace: freeSpace,
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                return url.path.hasPrefix(drive.path) ? HangingStem(writer, gate: gate) : writer
            },
            destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300), writeAbandoned: writeAbandoned)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        return recorder
    }

    @Test("Stop leaves a Drive it gave up on alone: its Show.json isn't written (#652)", .timeLimit(.minutes(3)))
    func stuckDriveShowFileUntouched() async throws {
        let gate = Gate()
        defer { gate.open() }
        let device = root.appending(path: "Device"), drive = root.appending(path: "Drive")
        let recorder = try recordingOnStuckDrive(gate: gate, device: device, drive: drive)
        try await Task.sleep(for: .milliseconds(100))
        let showFile = drive.appending(path: "\(show)/Show.json")
        let before = try Data(contentsOf: showFile)

        try await recorder.stopTake()
        #expect(recorder.copies[.drive] == .hasGaps)
        #expect(try Data(contentsOf: showFile) == before, "Stop wrote the abandoned Drive's Show.json")
        gate.open()
        await recorder.waitForRepair()
    }

    @Test("Stop doesn't write a Drive it gave up on: its Take.json gets the tail Gap later, off Stop (#652)", .timeLimit(.minutes(3)))
    func stuckDriveTakeFileWrittenLater() async throws {
        let gate = Gate()
        defer { gate.open() }
        let device = root.appending(path: "Device"), drive = root.appending(path: "Drive")
        let recorder = try recordingOnStuckDrive(gate: gate, device: device, drive: drive)
        try await Task.sleep(for: .milliseconds(100))
        let take = drive.appending(path: "\(show)/Take 01")
        let before = try Data(contentsOf: take.appending(path: "Take.json"))

        try await recorder.stopTake()
        #expect(try Data(contentsOf: take.appending(path: "Take.json")) == before, "Stop wrote the abandoned Drive's Take.json")
        gate.open()
        await recorder.waitForRepair()
        #expect(try TakeMetadata.read(fromTakeFolder: take).outcome(ofCopy: .drive) == .hasGaps)
    }

    @Test("A Drive Stop gave up on gets its Take.json off the main thread, Stop's first and Repair's after it (#652)", .timeLimit(.minutes(3)))
    func stuckDriveWrittenOffMainInOrder() async throws {
        let gate = Gate()
        let writes = AbandonedWrites()
        defer { gate.open(); writes.release() }
        let device = root.appending(path: "Device"), drive = root.appending(path: "Drive")
        let recorder = try recordingOnStuckDrive(gate: gate, device: device, drive: drive, writeAbandoned: writes.write)
        try await Task.sleep(for: .milliseconds(100))

        // Stop returns while the Drive hangs on its Take.json.
        let started = ContinuousClock.now
        try await recorder.stopTake()
        // A write on the main thread would hold Stop for `hangGuard`.
        #expect(ContinuousClock.now - started < .seconds(30), "Stop waited on the abandoned Drive's Take.json")
        gate.open()
        try await waitUntil { writes.calls.count >= 1 }
        writes.release()
        await recorder.waitForRepair()
        try await waitUntil { writes.calls.count >= 2 }
        // Repair's write comes only once Stop's is done, so it can't overwrite Stop's with an older one.
        #expect(!writes.secondStartedEarly, "Repair wrote the abandoned Drive before Stop's write was done")
        #expect(writes.calls == [false, false], "an abandoned Drive's Take.json was written on the main thread")
    }

    @Test("Stop doesn't ask a Drive it gave up on for its free space (#652)", .timeLimit(.minutes(3)))
    func stuckDriveNotAskedForSpace() async throws {
        let gate = Gate()
        defer { gate.open() }
        let asked = Asked()
        let device = root.appending(path: "Device"), drive = root.appending(path: "Drive")
        let recorder = try recordingOnStuckDrive(gate: gate, device: device, drive: drive, freeSpace: { asked.add($0); return .max })
        try await Task.sleep(for: .milliseconds(100))
        asked.urls = []

        try await recorder.stopTake()
        #expect(!asked.urls.contains { $0.path.hasPrefix(drive.path) }, "asked the abandoned Drive for its free space")
        gate.open()
        await recorder.waitForRepair()
    }

    final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var _urls: [URL] = []
        var urls: [URL] { get { lock.withLock { _urls } } set { lock.withLock { _urls = newValue } } }
        func add(_ url: URL) { lock.withLock { _urls.append(url) } }
    }

    @Test("Stop waits on every stuck Copy at once, not one after the other (#652)", .timeLimit(.minutes(3)))
    func stuckDeviceAndDrive() async throws {
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let gate = Gate()
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in HangingStem(try StemWriter.open(url: url, info: info, resumingAt: resume), gate: gate) },
            destinationCheckInterval: nil, writerStopTimeout: .seconds(3),
            // Inline: the 3 s against 6 s bound below is too tight to measure across a return to the main actor.
            asyncStopAvailable: false)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await Task.sleep(for: .milliseconds(100))

        // One after the other, two stuck Copies hold Stop for at least 6 s; at once, about 3 s.
        let started = ContinuousClock.now
        try await recorder.stopTake()
        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= .seconds(3), "Stop didn't wait on the stuck Copies")
        #expect(elapsed < .seconds(5), "Stop waited on the stuck Copies one after the other")
        #expect(recorder.copies[.device] == .hasGaps)
        #expect(recorder.copies[.drive] == .hasGaps)
        gate.open()
        await recorder.waitForRepair()
    }

    @Test("When Stop gives up on a stuck Drive Copy, it writes the report and Reaper project on the Device Copy only")
    func stuckDriveGetsNoReport() async throws {
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let gate = Gate()
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resume in
                let writer = try StemWriter.open(url: url, info: info, resumingAt: resume)
                return url.path.hasPrefix(drive.path) ? HangingStem(writer, gate: gate) : writer
            },
            destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300))
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await Task.sleep(for: .milliseconds(100))
        try await recorder.stopTake()

        #expect(FileManager.default.fileExists(atPath: device.appending(path: "\(show)/Report.html").path))
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "\(show)/\(show).RPP").path))
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/Report.html").path))
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/\(show).RPP").path))
        gate.open()
        await recorder.waitForRepair()
        // Nor once Repair is done (#652).
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/Report.html").path))
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/\(show).RPP").path))
    }

    @Test("The report and Reaper project are never written during a Take: a Repair that finishes mid-Take leaves them for the Take's end")
    func noReportsMidTake() async throws {
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let available = DriveSwitch()
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { available.folder.map { DriveAccess(folder: $0) } },
            now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        // Take 1: the Drive joins late, so the Take ends with a Gap that Repair will fill.
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        available.folder = drive
        await recorder.checkDestinations()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try await recorder.stopTake()

        // Take 2 starts before that Repair is done; its end must not write the report mid-Take.
        try recorder.startTake()
        let report = device.appending(path: "\(show)/Report.html")
        try? FileManager.default.removeItem(at: report)
        await recorder.waitForRepair()
        #expect(!FileManager.default.fileExists(atPath: report.path), "written during Take 2")

        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(FileManager.default.fileExists(atPath: report.path))
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "\(show)/\(show).RPP").path))
    }
}

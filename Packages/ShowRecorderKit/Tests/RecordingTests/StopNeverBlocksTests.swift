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

    final class Gate: @unchecked Sendable {
        private let lock = NSCondition()
        private var stalled = true
        func wait() { lock.lock(); while stalled { lock.wait() }; lock.unlock() }
        func open() { lock.lock(); stalled = false; lock.broadcast(); lock.unlock() }
    }
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

    @Test("A Drive stuck on a write doesn't hold up Stop: the Take ends, the Device Copy is complete, the Drive Copy is interrupted and never written again")
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
        try recorder.stopTake()
        #expect(ContinuousClock.now - started < .seconds(2), "Stop waited on the stuck Drive")
        #expect(!recorder.isRecording)
        #expect(recorder.copyStatus(.drive) == .interrupted)
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
        try recorder.stopTake()

        #expect(FileManager.default.fileExists(atPath: device.appending(path: "\(show)/Report.html").path))
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "\(show)/\(show).RPP").path))
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/Report.html").path))
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/\(show).RPP").path))
        gate.open()
        await recorder.waitForRepair()
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
        recorder.checkDestinations()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try recorder.stopTake()

        // Take 2 starts before that Repair is done; its end must not write the report mid-Take.
        try recorder.startTake()
        let report = device.appending(path: "\(show)/Report.html")
        try? FileManager.default.removeItem(at: report)
        await recorder.waitForRepair()
        #expect(!FileManager.default.fileExists(atPath: report.path), "written during Take 2")

        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(FileManager.default.fileExists(atPath: report.path))
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "\(show)/\(show).RPP").path))
    }
}

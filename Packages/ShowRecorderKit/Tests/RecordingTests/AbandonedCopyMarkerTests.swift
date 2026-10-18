import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// A Copy Stop gave up on is marked in Take.json, so a later launch can find it and finish it (#817).
@MainActor
@Suite("Abandoned Copy marker")
struct AbandonedCopyMarkerTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "AbandonedCopyMarkerTests-\(UUID().uuidString)")
    let show = "2026-10-06 Show"

    private func metadata() -> TakeMetadata {
        TakeMetadata(
            show: show, take: 1, startedAt: Date(timeIntervalSince1970: 1_000), sampleRate: 48_000, timeReference: 0,
            usbChannels: [])
    }

    @Test("The marker survives Take.json, and a Take without one doesn't mention it")
    func roundTrip() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var marked = metadata()
        marked.abandonedCopies = [.drive]
        try marked.write(to: root)
        #expect(try TakeMetadata.read(fromTakeFolder: root).abandonedCopies == [.drive])
        try metadata().write(to: root)
        let json = try String(contentsOf: root.appending(path: TakeMetadata.fileName), encoding: .utf8)
        #expect(!json.contains("abandonedCopies"))
        #expect(try TakeMetadata.read(fromTakeFolder: root).abandonedCopies == nil)
    }

    @Test("A Drive Copy Stop gave up on is marked in the Device's Take.json; a Take that finished normally has no marker")
    func stopMarksTheAbandonedCopy() async throws {
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
                return url.path.hasPrefix(drive.path) ? StopNeverBlocksTests.HangingStem(writer, gate: gate) : writer
            },
            destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300))
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await Task.sleep(for: .milliseconds(100))
        try await recorder.stopTake()
        await recorder.waitForRepair()
        let take = device.appending(path: "\(show)/Take 01")
        #expect(try TakeMetadata.read(fromTakeFolder: take).abandonedCopies == [.drive])

        // The next Take finishes normally (the Drive wakes up): no marker.
        gate.open()
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 4_800)])
        try await Task.sleep(for: .milliseconds(100))
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(try TakeMetadata.read(fromTakeFolder: device.appending(path: "\(show)/Take 02")).abandonedCopies == nil)
    }
}

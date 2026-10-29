import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Testing

/// A record press that fails must not block the next one (#315).
@MainActor
@Suite("Failed record press")
struct FailedPressTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "FailedPressTests-\(UUID().uuidString)")
    let show = "2026-10-06 Show"

    final class Switch: @unchecked Sendable { var failing = true }

    func entries(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    @Test("A press that fails leaves no Take folder behind, and the next press records Take 01")
    func failThenRecord() async throws {
        let fail = Switch()
        let device = root.appending(path: "Device")
        let recorder = Recorder(deviceFolder: device, now: { RecordingTakeTests.showDay }, makeStem: { url, info, resume in
            if fail.failing { throw CocoaError(.fileWriteOutOfSpace) }
            return try StemWriter.open(url: url, info: info, resumingAt: resume)
        })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)

        #expect(throws: (any Error).self) { try recorder.startTake() }
        #expect(!recorder.isRecording)
        #expect(!entries(device.appending(path: show)).contains("Take 01"), "the failed press cleans up its folder")

        fail.failing = false
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.1, count: 480), Array(repeating: 0.1, count: 480)])
        try await recorder.stopTake()
        #expect(entries(device.appending(path: show)).filter { $0.hasPrefix("Take") } == ["Take 01"])
        #expect(entries(device.appending(path: "\(show)/Take 01")).contains("01 USB 01.wav"))
    }

    @Test("A Drive that fails at the press doesn't stop the Take: it records to the Device")
    func driveFailsAtPress() async throws {
        let device = root.appending(path: "Device")
        // A file where the Drive's folder should be: creating the Show folder in it fails.
        let notAFolder = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: notAFolder)
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: notAFolder) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)

        try recorder.startTake()
        #expect(recorder.isRecording)
        audio.deliver([Array(repeating: 0.1, count: 480), Array(repeating: 0.1, count: 480)])
        try await recorder.stopTake()
        #expect(entries(device.appending(path: "\(show)/Take 01")).contains("01 USB 01.wav"))
    }

    @Test("A failed press never deletes a Take folder that was already there")
    func keepsExistingFolder() throws {
        let device = root.appending(path: "Device")
        let recorder = Recorder(deviceFolder: device, now: { RecordingTakeTests.showDay })
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 2))
        try recorder.startNewShow(name: "", venue: "")
        // A "Take 01" already on disk (left by something else): the press can't use that number.
        let existing = device.appending(path: "\(show)/Take 01")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: existing.appending(path: "01 Kick.wav"))

        #expect(throws: (any Error).self) { try recorder.startTake() }
        #expect(FileManager.default.fileExists(atPath: existing.appending(path: "01 Kick.wav").path))
    }
}

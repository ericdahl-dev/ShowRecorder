import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Testing

/// The Recorder watches its Destinations on its own while a Take runs, and says why each Take ended.
@MainActor
@Suite("Why a Take ended")
struct TakeEndTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "TakeEndTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    func deliverBlocks(_ count: Int, to audio: FakeAudioDevice, _ recorder: Recorder) async throws {
        for _ in 0..<count {
            audio.deliver([[Float](repeating: 0, count: 480)])
            try await waitUntil { recorder.bufferedFrameCount == 0 }
        }
    }

    @Test("A Take whose last Destination is about to fill ends by itself, and says so")
    func outOfSpace() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let free = FreeSpace(device: 100_000_000, drive: 100_000_000)
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            freeSpace: { free.bytes(at: $0) },
            destinationCheckInterval: .milliseconds(10))
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder)
        free.device = 5_000_000
        free.drive = 5_000_000
        try await waitUntil { !recorder.isRecording }

        #expect(!recorder.isRecording)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .outOfSpace))
    }

    @Test("A Take that no Destination can be written to any more ends, and says so")
    func noDestination() async throws {
        // Device only: a Drive Copy that fails can rejoin when the Drive is checked again, which is right.
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(
            deviceFolder: device,
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in FailingStem(try StemWriter.open(url: url, info: info, resumingAt: resuming), healthyFrames: 480) },
            destinationCheckInterval: .milliseconds(10))
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder)
        try await waitUntil { !recorder.isRecording }

        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .noDestination))
    }

    @Test("A Drive that appears mid-Take joins it without anyone asking the Recorder to look")
    func driveJoinsOnItsOwn() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let available = DriveAvailability()
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { available.isOn ? DriveAccess(folder: drive) : nil },
            now: { RecordingTakeTests.showDay },
            destinationCheckInterval: .milliseconds(10))
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder)
        available.isOn = true
        try await waitUntil { recorder.copyStatus(.drive) == .recording }

        #expect(recorder.copyStatus(.drive) == .recording)
        try recorder.stopTake()
    }

    @Test("Only a Take the recorder ended has something to tell the operator, and both say the audio was saved")
    func messages() {
        #expect(TakeEnd.Reason.stopped.message == nil)
        #expect(TakeEnd.Reason.outOfSpace.message == "Recording stopped because the last Destination was about to fill. Everything recorded was saved.")
        #expect(TakeEnd.Reason.noDestination.message == "Recording stopped because no Destination could be written. Everything recorded so far was saved.")
    }

    @Test("Each Take's end is its own: stopping two Takes gives Take 1 then Take 2, both stopped")
    func stoppedTakesInTurn() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, now: { RecordingTakeTests.showDay }, destinationCheckInterval: .milliseconds(10))
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(1, to: audio, recorder)
        try recorder.stopTake()
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .stopped))

        try recorder.startTake()
        try await deliverBlocks(1, to: audio, recorder)
        try recorder.stopTake()
        #expect(recorder.lastTakeEnd == TakeEnd(take: 2, reason: .stopped))
    }
}

@MainActor
final class DriveAvailability {
    var isOn = false
}

import AudioIO
import Foundation
import Testing

@testable import Recording

/// Which channels have reached full scale, kept by the recorder until the operator clears them.
@MainActor
@Suite("Clip indicator")
struct ClipIndicatorTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ClipIndicatorTests-\(UUID().uuidString)")

    func recorder() -> Recorder {
        Recorder(deviceFolder: folder, driveFolder: { nil }, now: { RecordingTakeTests.showDay })
    }

    @Test("A channel that reaches full scale is marked clipped and stays marked; -0.5 dBFS isn't a clip")
    func marksAndKeeps() throws {
        let device = FakeAudioDevice(inputChannelCount: 3)
        let recorder = Recorder()
        try recorder.arm(device)

        device.deliver([[0.1, 1.0, 0.2], [0.944, -0.5, 0.1], [-1.0, 0, 0]])  // channel 2 clips on a negative peak
        _ = recorder.takeChannelLevels()
        #expect(recorder.clippedChannels == [0, 2])

        device.deliver([[0.1], [0.1], [0.1]])
        _ = recorder.takeChannelLevels()
        #expect(recorder.clippedChannels == [0, 2], "the mark stays after the signal drops")
    }

    @Test("Clearing a channel's mark leaves the others, and a channel can clip again afterwards")
    func clearsOne() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder()
        try recorder.arm(device)
        device.deliver([[1.0], [1.0]])
        _ = recorder.takeChannelLevels()
        #expect(recorder.clippedChannels == [0, 1])

        recorder.clearClip(channel: 0)
        #expect(recorder.clippedChannels == [1])

        device.deliver([[1.0], [0.1]])
        _ = recorder.takeChannelLevels()
        #expect(recorder.clippedChannels == [0, 1])
    }

    @Test("Starting a Take clears the marks; a clip during the Take stays marked after it ends")
    func nextTakeClears() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(device)
        device.deliver([[1.0]])
        _ = recorder.takeChannelLevels()
        #expect(recorder.clippedChannels == [0])

        try recorder.startTake()
        #expect(recorder.clippedChannels.isEmpty)
        device.deliver([[1.0]])
        _ = recorder.takeChannelLevels()
        try recorder.stopTake()
        #expect(recorder.clippedChannels == [0], "still marked after the Take, until tapped or the next Take")

        try recorder.startTake()
        #expect(recorder.clippedChannels.isEmpty)
        try recorder.stopTake()
    }

    @Test("Disarming clears the marks: the next input's channels aren't these ones")
    func disarmClears() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(device)
        device.deliver([[1.0]])
        _ = recorder.takeChannelLevels()
        recorder.disarm()
        #expect(recorder.clippedChannels.isEmpty)
    }
}

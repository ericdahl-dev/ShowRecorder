import AudioIO
import Recording
import Testing

@MainActor
@Suite("Ready recorder")
struct ReadyRecorderTests {
    @Test("Getting ready reports the device's USB Channel count")
    func gettingReadyReportsUSBChannelCount() throws {
        let device = FakeAudioDevice(inputChannelCount: 18)
        let recorder = Recorder()

        try recorder.getReady(device)

        #expect(recorder.isReady)
        #expect(recorder.usbChannelCount == 18)
    }

    @Test("Any channel count is Ready as-is", arguments: [2, 8, 16, 18, 32])
    func anyChannelCountIsReady(channels: Int) throws {
        let recorder = Recorder()

        try recorder.getReady(FakeAudioDevice(inputChannelCount: channels))

        #expect(recorder.isReady)
        #expect(recorder.usbChannelCount == channels)
    }

    @Test("Meters show each USB Channel's peak level while Ready")
    func metersShowPeakPerChannel() throws {
        let device = FakeAudioDevice(inputChannelCount: 3)
        let recorder = Recorder()
        try recorder.getReady(device)

        device.deliver([
            [0.0, 0.25, -0.1, 0.0],
            [0.5, -0.75, 0.0, 0.2],  // negative peak counts by magnitude
            [0.0, 0.0, 0.0, 0.0],
        ])

        #expect(recorder.takeMeterLevels() == [0.25, 0.75, 0.0])
    }

    @Test("The meter levels also give each channel's average level and frame count")
    func channelLevelsGiveAverages() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder()
        try recorder.getReady(device)

        device.deliver([[0.5, -0.5, 0.25, -0.25], [0, 0, 0, 0]])

        let levels = recorder.takeChannelLevels()
        #expect(levels.count == 2)
        #expect(levels[0].peak == 0.5 && levels[0].frames == 4)
        #expect(abs(levels[0].meanRectified - 0.375) < 1e-6)
        #expect(levels[1] == ChannelLevel(peak: 0, meanRectified: 0, frames: 4))
        #expect(recorder.takeChannelLevels().allSatisfy { $0.frames == 0 })
    }

    @Test("Meters reset after each reading")
    func metersResetAfterReading() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder()
        try recorder.getReady(device)

        device.deliver([[0.9], [0.4]])
        _ = recorder.takeMeterLevels()
        device.deliver([[0.1], [0.2]])

        #expect(recorder.takeMeterLevels() == [0.1, 0.2])
    }

    @Test("Standing down stops the device and clears the meters")
    func standingDownStopsDeviceAndClearsMeters() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder()
        try recorder.getReady(device)

        recorder.standDown()
        device.deliver([[0.5], [0.5]])

        #expect(!recorder.isReady)
        #expect(!device.isRunning)
        #expect(recorder.takeMeterLevels().isEmpty)
        #expect(recorder.usbChannelCount == 0)
    }

    @Test("Getting a different device stops the previous ready one")
    func gettingReadyAnotherDeviceStopsThePreviousOne() throws {
        let first = FakeAudioDevice(inputChannelCount: 18)
        let second = FakeAudioDevice(inputChannelCount: 8)
        let recorder = Recorder()

        try recorder.getReady(first)
        try recorder.getReady(second)

        #expect(!first.isRunning)
        #expect(second.isRunning)
        #expect(recorder.usbChannelCount == 8)
    }
}

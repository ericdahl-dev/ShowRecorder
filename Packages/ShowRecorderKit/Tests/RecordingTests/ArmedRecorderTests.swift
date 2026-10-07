import AudioIO
import Recording
import Testing

@MainActor
@Suite("Armed recorder")
struct ArmedRecorderTests {
    @Test("Arming reports the device's USB Channel count")
    func armingReportsUSBChannelCount() throws {
        let device = FakeAudioDevice(inputChannelCount: 18)
        let recorder = Recorder()

        try recorder.arm(device)

        #expect(recorder.isArmed)
        #expect(recorder.usbChannelCount == 18)
    }

    @Test("Any channel count is Armed as-is", arguments: [2, 8, 16, 18, 32])
    func anyChannelCountIsArmed(channels: Int) throws {
        let recorder = Recorder()

        try recorder.arm(FakeAudioDevice(inputChannelCount: channels))

        #expect(recorder.isArmed)
        #expect(recorder.usbChannelCount == channels)
    }

    @Test("Meters show each USB Channel's peak level while Armed")
    func metersShowPeakPerChannel() throws {
        let device = FakeAudioDevice(inputChannelCount: 3)
        let recorder = Recorder()
        try recorder.arm(device)

        device.deliver([
            [0.0, 0.25, -0.1, 0.0],
            [0.5, -0.75, 0.0, 0.2],  // negative peak counts by magnitude
            [0.0, 0.0, 0.0, 0.0],
        ])

        #expect(recorder.takeMeterLevels() == [0.25, 0.75, 0.0])
    }

    @Test("Meters reset after each reading")
    func metersResetAfterReading() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder()
        try recorder.arm(device)

        device.deliver([[0.9], [0.4]])
        _ = recorder.takeMeterLevels()
        device.deliver([[0.1], [0.2]])

        #expect(recorder.takeMeterLevels() == [0.1, 0.2])
    }

    @Test("Disarming stops the device and clears the meters")
    func disarmingStopsDeviceAndClearsMeters() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder()
        try recorder.arm(device)

        recorder.disarm()
        device.deliver([[0.5], [0.5]])

        #expect(!recorder.isArmed)
        #expect(!device.isRunning)
        #expect(recorder.takeMeterLevels().isEmpty)
        #expect(recorder.usbChannelCount == 0)
    }

    @Test("Arming a different device stops the previous one")
    func armingAnotherDeviceStopsThePreviousOne() throws {
        let first = FakeAudioDevice(inputChannelCount: 18)
        let second = FakeAudioDevice(inputChannelCount: 8)
        let recorder = Recorder()

        try recorder.arm(first)
        try recorder.arm(second)

        #expect(!first.isRunning)
        #expect(second.isRunning)
        #expect(recorder.usbChannelCount == 8)
    }
}

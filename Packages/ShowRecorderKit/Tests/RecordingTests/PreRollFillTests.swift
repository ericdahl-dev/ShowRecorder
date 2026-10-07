import AudioIO
import Foundation
@testable import Recording
import Testing

/// While Armed the recorder keeps the last seconds of audio for Pre-roll.
@MainActor
@Suite("Filling the Pre-roll while Armed")
struct PreRollFillTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "PreRollFillTests-\(UUID().uuidString)")

    /// Delivers `count` frames of a ramp (value = absolute frame index, plus `channel * 1_000_000`) in blocks.
    func deliver(_ count: Int, from start: Int = 0, to device: FakeAudioDevice, block: Int = 480) {
        var frame = start
        while frame < start + count {
            let n = min(block, start + count - frame)
            device.deliver((0..<device.inputChannelCount).map { channel in (0..<n).map { Float(frame + $0 + channel * 1_000_000) } })
            frame += n
        }
    }

    @Test("An Armed recorder holds the last N seconds of every channel, exactly")
    func holdsLastSeconds() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, preRollSeconds: 1)
        try recorder.arm(device)
        deliver(72_000, to: device)

        let snapshot = try #require(recorder.armedPreRoll).snapshot(maxFrames: 48_000)
        #expect(snapshot.startFrame == 24_000)
        #expect(snapshot.channels[0] == (24_000..<72_000).map { Float($0) })
        #expect(snapshot.channels[1] == (24_000..<72_000).map { Float($0 + 1_000_000) })
    }

    @Test("Arming again starts with an empty buffer")
    func rearmEmpties() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, preRollSeconds: 1)
        try recorder.arm(device)
        deliver(10_000, to: device)
        #expect(try #require(recorder.armedPreRoll).totalWrittenFrames == 10_000)

        try recorder.arm(device)
        #expect(try #require(recorder.armedPreRoll).totalWrittenFrames == 0)
    }

    @Test("Moving to a device with a different format empties it; the same format keeps it")
    func deviceChange() throws {
        let first = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, preRollSeconds: 1)
        try recorder.arm(first)
        deliver(5_000, to: first)

        let same = FakeAudioDevice(inputChannelCount: 2)
        #expect(try recorder.restartInput(on: same))
        #expect(try #require(recorder.armedPreRoll).totalWrittenFrames == 5_000)
        deliver(1_000, from: 5_000, to: same)
        #expect(try #require(recorder.armedPreRoll).totalWrittenFrames == 6_000)

        let different = FakeAudioDevice(inputChannelCount: 4)
        #expect(try !recorder.restartInput(on: different))
        let buffer = try #require(recorder.armedPreRoll)
        #expect(buffer.channelCount == 4)
        #expect(buffer.totalWrittenFrames == 0)
    }

    @Test("With Pre-roll off there is no buffer, and disarming drops it")
    func offAndDisarm() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let off = Recorder(deviceFolder: root, preRollSeconds: 0)
        try off.arm(device)
        #expect(off.armedPreRoll == nil)

        let on = Recorder(deviceFolder: root, preRollSeconds: 1)
        try on.arm(device)
        #expect(on.armedPreRoll != nil)
        on.disarm()
        #expect(on.armedPreRoll == nil)
    }

    @Test("The buffer keeps filling during a Take")
    func fillsDuringTake() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, preRollSeconds: 1)
        try recorder.arm(device)
        deliver(2_000, to: device)
        try recorder.startTake()
        deliver(3_000, from: 2_000, to: device)
        try recorder.stopTake()
        #expect(try #require(recorder.armedPreRoll).totalWrittenFrames == 5_000)
    }
}

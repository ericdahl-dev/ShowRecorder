import AudioIO
import Foundation
@testable import Recording
import Testing

/// While Ready the recorder keeps the last seconds of audio for Pre-roll.
@MainActor
@Suite("Filling the Pre-roll while Ready")
struct PreRollFillTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "PreRollFillTests-\(UUID().uuidString)")

    /// Each sample is its frame plus a million per channel, unscaled, so the Pre-roll can be read back exactly.
    static func value(_ frame: Int, _ channel: Int) -> Float { Float(frame + channel * 1_000_000) }

    @Test("A Ready recorder holds the last N seconds of every channel, exactly")
    func holdsLastSeconds() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, preRollSeconds: 1)
        try recorder.getReady(device)
        deliver(72_000, to: device, block: 480, sample: Self.value)

        let buffer = try #require(recorder.readyPreRoll)
        let held = try #require(buffer.read(frames: 24_000..<72_000))
        #expect(held[0] == (24_000..<72_000).map { Float($0) })
        #expect(held[1] == (24_000..<72_000).map { Float($0 + 1_000_000) })
    }

    @Test("Getting ready again starts with an empty buffer")
    func getReadyAgainEmpties() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, preRollSeconds: 1)
        try recorder.getReady(device)
        deliver(10_000, to: device, block: 480, sample: Self.value)
        #expect(try #require(recorder.readyPreRoll).totalWrittenFrames == 10_000)

        try recorder.getReady(device)
        #expect(try #require(recorder.readyPreRoll).totalWrittenFrames == 0)
    }

    @Test("Moving to a device with a different format empties it; the same format keeps it")
    func deviceChange() async throws {
        let first = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, preRollSeconds: 1)
        try recorder.getReady(first)
        deliver(5_000, to: first, block: 480, sample: Self.value)

        let same = FakeAudioDevice(inputChannelCount: 2)
        #expect(try await recorder.restartInput(on: same))
        #expect(try #require(recorder.readyPreRoll).totalWrittenFrames == 5_000)
        deliver(1_000, from: 5_000, to: same, block: 480, sample: Self.value)
        #expect(try #require(recorder.readyPreRoll).totalWrittenFrames == 6_000)

        let different = FakeAudioDevice(inputChannelCount: 4)
        let continuedOnDifferent = try await recorder.restartInput(on: different)
        #expect(!continuedOnDifferent)
        let buffer = try #require(recorder.readyPreRoll)
        #expect(buffer.channelCount == 4)
        #expect(buffer.totalWrittenFrames == 0)
    }

    @Test("With Pre-roll off the buffer only has room for a Take that starts late, and standing down drops it")
    func offAndStandDown() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let off = Recorder(deviceFolder: root, preRollSeconds: 0)
        try off.getReady(device)
        #expect(off.readyPreRoll != nil, "room for the start wait (#915)")
        off.standDown()
        #expect(off.readyPreRoll == nil)

        let on = Recorder(deviceFolder: root, preRollSeconds: 1)
        try on.getReady(device)
        #expect(on.readyPreRoll != nil)
        on.standDown()
        #expect(on.readyPreRoll == nil)
    }

    @Test("The buffer keeps filling during a Take")
    func fillsDuringTake() async throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, preRollSeconds: 1)
        try recorder.getReady(device)
        deliver(2_000, to: device, block: 480, sample: Self.value)
        try recorder.startTake()
        deliver(3_000, from: 2_000, to: device, block: 480, sample: Self.value)
        try await recorder.stopTake()
        #expect(try #require(recorder.readyPreRoll).totalWrittenFrames == 5_000)
    }
}

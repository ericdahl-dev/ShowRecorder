import AudioIO
import Foundation
import Testing

@testable import Recording

/// A Take's peak and average level per channel, from the windows the meter reads.
@MainActor
@Suite("Take levels")
struct TakeLevelsTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "TakeLevelsTests-\(UUID().uuidString)")

    func metadata() throws -> TakeMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = try Data(contentsOf: folder.appending(path: "2026-10-06 Show/Take 01/Take.json"))
        return try decoder.decode(TakeMetadata.self, from: json)
    }

    @Test("Peak is the loudest window; the average is the power average of the VU levels, weighted by frames")
    func peakAndPowerAverage() {
        var levels = TakeLevels(channelCount: 2)
        levels.add([
            ChannelLevel(peak: 0.2, meanRectified: 0.1, frames: 1_000),
            ChannelLevel(peak: 0, meanRectified: 0, frames: 1_000),
        ])
        levels.add([
            ChannelLevel(peak: 0.5, meanRectified: 0.3, frames: 3_000),
            ChannelLevel(peak: 0, meanRectified: 0, frames: 3_000),
        ])
        let a = 0.1 * VUMeter.formFactor, b = 0.3 * VUMeter.formFactor
        let expected = 20 * log10(((a * a * 1_000 + b * b * 3_000) / 4_000).squareRoot())
        let result = levels.summary
        #expect(abs(result[0].peakDbfs - 20 * log10(0.5)) < 1e-5)
        #expect(abs(result[0].averageDbfs - expected) < 1e-5)
        #expect(result[1].peakDbfs == VUMeter.floorDbfs && result[1].averageDbfs == VUMeter.floorDbfs, "silence reads the floor, not minus infinity")
    }

    @Test("Take.json holds each channel's peak and average from the press: audio before it isn't counted, and silence reads the floor")
    func takeJSONHasLevels() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: folder, driveFolder: { nil }, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        device.deliver([Array(repeating: 0.9, count: 4_800), Array(repeating: 0, count: 4_800)])  // before the press
        try recorder.startTake()
        for _ in 0..<5 {
            device.deliver([Array(repeating: 0.1, count: 4_800), Array(repeating: 0, count: 4_800)])
            _ = recorder.takeChannelLevels()
        }
        device.deliver([Array(repeating: -0.1, count: 480), Array(repeating: 0, count: 480)])  // not read by the screen
        try recorder.stopTake()

        let channels = try metadata().usbChannels
        let peak = try #require(channels[0].peakDbfs), average = try #require(channels[0].averageDbfs)
        #expect(abs(peak - 20 * log10(0.1)) < 0.01, "peak \(peak), not the 0.9 from before the press")
        // A constant 0.1 has an average rectified level of 0.1, which reads 0.1 times the form factor.
        #expect(abs(average - 20 * log10(0.1 * VUMeter.formFactor)) < 0.01, "average \(average)")
        #expect(channels[1].peakDbfs == VUMeter.floorDbfs && channels[1].averageDbfs == VUMeter.floorDbfs)
    }
}

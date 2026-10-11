import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// A whole Take, Repair included, at rates other than 48 kHz (#195, #323): every file carries the real rate.
@MainActor
@Suite("Takes at other sample rates")
struct SampleRateTakeTests {
    let show = "2026-10-06 Show"

    @Test("A Take at 44.1 or 96 kHz: Stems, Take.json, Repair and the Reaper project all use that rate", arguments: [44_100, 96_000])
    func takeAtRate(rate: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SampleRateTakeTests-\(UUID().uuidString)")
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let available = DriveSwitch()
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { available.folder.map { DriveAccess(folder: $0) } },
            now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 2, sampleRate: Double(rate))
        try recorder.arm(audio)
        #expect(recorder.sampleRate == rate)

        try recorder.startTake()
        // Half a second, then the Drive joins (a Gap before it), then another half second.
        let half = rate / 2
        audio.deliver([Array(repeating: 0.25, count: half), Array(repeating: 0.5, count: half)])
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        available.folder = drive
        recorder.checkDestinations()
        audio.deliver([Array(repeating: 0.25, count: half), Array(repeating: 0.5, count: half)])
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try recorder.stopTake()
        await recorder.waitForRepair()

        for parent in [device, drive] {
            let take = parent.appending(path: "\(show)/Take 01")
            let stem = take.appending(path: "01 USB 01.wav")
            #expect(try StemFile(contentsOf: stem).sampleRate == rate, "\(parent.lastPathComponent) header rate")
            #expect(try StemLength.frameCount(at: stem) == UInt64(2 * half), "\(parent.lastPathComponent) length")
        }
        let metadata = try TakeMetadata.read(fromTakeFolder: device.appending(path: "\(show)/Take 01"))
        #expect(metadata.sampleRate == rate)
        #expect(metadata.gaps.contains { $0.copy == .drive })
        #expect(try Data(contentsOf: drive.appending(path: "\(show)/Take 01/01 USB 01.wav"))
            == Data(contentsOf: device.appending(path: "\(show)/Take 01/01 USB 01.wav")), "Repair filled the Drive at \(rate)")

        let project = try String(contentsOf: device.appending(path: "\(show)/\(show).RPP"), encoding: .utf8)
        #expect(project.contains("SAMPLERATE \(rate) "))
        #expect(project.contains("LENGTH 1.0000000000"), "a 1 s Take is 1 s long in Reaper at \(rate)")
    }
}

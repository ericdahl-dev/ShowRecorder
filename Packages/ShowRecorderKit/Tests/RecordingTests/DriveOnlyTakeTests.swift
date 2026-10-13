import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#196, ADR 0006): a Take is written to the Drive alone. The Device stands in only for what the Drive
/// couldn't take, and Repair moves that to the Drive after the Take.
@MainActor
@Suite("Drive only Takes")
struct DriveOnlyTakeTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "DriveOnlyTakeTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let take = "2026-10-06 Show/Take 01"

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// A Drive only recorder; the Drive Copy's Stems are made by `driveStem` (a real one by default).
    func recorder(driveStem: @escaping (StemWriter) -> any StemSink = { $0 }, stallLimit: Duration = .seconds(2)) -> Recorder {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                return url.path.hasPrefix(drive.path) && resuming == nil ? driveStem(real) : real
            }, destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300), driveStallLimit: stallLimit)
        recorder.recordsToDriveOnly = true
        return recorder
    }

    /// Every sample of the Drive Copy's Stem.
    func driveSamples(frames: Int) throws -> [Float] {
        try StemWriter.readSamples(url: drive.appending(path: "\(take)/01 USB 01.wav"), frames: 0..<frames)
    }

    @Test("With a healthy Drive, nothing of the Take is written to the Device")
    func healthyDrive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(try driveSamples(frames: 4_800) == (0..<4_800).map { counting()($0, 0) })
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "no Take folder on the Device")
    }

    @Test("A Drive that fails mid-Take: the Device stands in for the rest, and Repair moves it to the Drive and off the Device")
    func driveFails() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder { FailingStem($0, healthyFrames: 480) }
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }
        recorder.checkDestinations()
        try await deliverBlocks(5, from: 10 * 480, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(try driveSamples(frames: 7_200) == (0..<7_200).map { counting()($0, 0) }, "the Drive has the whole Take")
        #expect(recorder.lastTakeOutcomes[.drive] == .repaired)
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "nothing of the Take is left on the Device")
    }

    /// A Drive Stem that takes `healthyFrames`, then hangs on its next write until the gate opens (a Drive pulled
    /// mid-write often hangs rather than failing).
    final class BlockingStem: StemSink, @unchecked Sendable {
        let inner: StemWriter
        let gate: StopNeverBlocksTests.Gate
        let healthyFrames: Int
        init(_ inner: StemWriter, gate: StopNeverBlocksTests.Gate, healthyFrames: Int) {
            self.inner = inner
            self.gate = gate
            self.healthyFrames = healthyFrames
        }
        var frameCount: UInt64 { inner.frameCount }
        func append(_ samples: UnsafeBufferPointer<Float>) throws {
            if Int(inner.frameCount) + samples.count > healthyFrames { gate.wait() }
            try inner.append(samples)
        }
        func commitHeader() throws { try inner.commitHeader() }
        func finalize() throws { try inner.finalize() }
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try inner.setMarkers(markers) }
    }

    @Test("A Drive that hangs mid-Take is given up: the Device stands in from where it stopped, and Stop doesn't wait on it")
    func driveHangs() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(driveStem: { BlockingStem($0, gate: gate, healthyFrames: 4_800) }, stallLimit: .milliseconds(100))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        // The Drive hangs on the next write; audio keeps coming.
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        recorder.checkDestinations()
        for block in 21..<30 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        try await Task.sleep(for: .milliseconds(200))

        let started = ContinuousClock.now
        try recorder.stopTake()
        #expect(ContinuousClock.now - started < .seconds(1), "Stop waited on the hung Drive")
        await recorder.waitForRepair()

        // The Device holds the stand-in from the Drive's last frame to the end of the Take, and keeps it: the Drive
        // can't be Repaired.
        let deviceTake = try TakeMetadata.read(fromTakeFolder: device.appending(path: take))
        #expect(deviceTake.standIns == [.init(start: 4_800, end: 14_400)])
        let standIn = device.appending(path: "\(take)/Stand-in 4800/01 USB 01.wav")
        #expect(try StemWriter.readSamples(url: standIn, frames: 0..<9_600) == (4_800..<14_400).map { counting()($0, 0) })
        #expect(try StemFile.inspect(standIn).frameCount == 9_600, "the stand-in's Stem is finalized")
        #expect(recorder.lastTakeOutcomes[.drive] != .repaired)
    }
}

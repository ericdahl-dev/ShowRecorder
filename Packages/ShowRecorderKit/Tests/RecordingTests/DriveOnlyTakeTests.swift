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

    @Test("After a Drive only Take the Drive took whole, the summary speaks of the Drive alone (#550)")
    func summaryDriveComplete() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(CopySummary.ofLastTake(recorder.copies, dropoutCount: recorder.dropoutCount)?.text == "Drive copy: complete")
    }

    @Test("With its Drive, a Drive only Take's Copies say Drive only: the Device is standing by, the Drive recording")
    func copiesStandingBy() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())

        #expect(recorder.copies.isDriveOnly)
        #expect(recorder.copies[.device] == .standingBy)
        #expect(recorder.copies[.drive] == .recording)
        try recorder.stopTake()
        await recorder.waitForRepair()
    }

    @Test("A Drive only Take with no Drive at record says it records to this iPhone and moves to the Drive later (#550)")
    func noDriveAlert() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        recorder.recordsToDriveOnly = true
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())

        let alert = try #require(DestinationAlert.make(copies: recorder.copies))
        #expect(alert.id == "no-drive")
        #expect(alert.text == "No Drive: recording to this iPhone; it moves to the Drive when one is connected.")
        try recorder.stopTake()
        await recorder.waitForRepair()
    }

    @Test("After a Drive only Take with no Drive at all, the summary says it is on this iPhone until the Drive is back (#550)")
    func summaryNoDrive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        recorder.recordsToDriveOnly = true
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(CopySummary.ofLastTake(recorder.copies, dropoutCount: recorder.dropoutCount)?.text == "On this iPhone until the Drive is back")
    }

    @Test("Once the Drive fails, a Drive only Take's Copies say the Device is standing in and the Drive interrupted")
    func copiesStandingIn() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder { FailingStem($0, healthyFrames: 480) }
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }
        recorder.checkDestinations()

        #expect(recorder.copies.isDriveOnly)
        #expect(recorder.copies[.device] == .standingIn)
        #expect(recorder.copies[.drive] == .interrupted)
        try recorder.stopTake()
        await recorder.waitForRepair()
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

    @Test("After Repair moves a stand-in to the Drive, the summary says it moved from this iPhone (#550)")
    func summaryMoved() async throws {
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

        #expect(CopySummary.ofLastTake(recorder.copies, dropoutCount: recorder.dropoutCount)?.text
                == "Drive copy: Repaired · moved from this iPhone")
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

    @Test("A Drive that hangs mid-Take: the Device stands in, Stop doesn't wait on the Drive, and the stand-in stays on the Device")
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

        // The Device holds the stand-in to the end of the Take, from 2 s before the Drive's last frame (what a pulled
        // Drive may not have made durable; here the start of the Take), and keeps it: the Drive can't be Repaired.
        let deviceTake = try TakeMetadata.read(fromTakeFolder: device.appending(path: take))
        #expect(deviceTake.standIns == [.init(start: 0, end: 14_400)])
        let standIn = device.appending(path: "\(take)/Stand-in 0/01 USB 01.wav")
        #expect(try StemWriter.readSamples(url: standIn, frames: 0..<14_400) == (0..<14_400).map { counting()($0, 0) })
        #expect(try StemFile.inspect(standIn).frameCount == 14_400, "the stand-in's Stem is finalized")
        #expect(recorder.lastTakeOutcomes[.drive] != .repaired)
    }

    @Test("After a relaunch the next Take gets a new number, though the Device has no folder for the last one")
    func takeNumberSurvivesRelaunch() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let first = recorder()
        try first.arm(audio)
        try first.startTake()
        try await deliverBlocks(2, to: audio, first)
        try first.stopTake()
        await first.waitForRepair()
        first.disarm()

        let relaunched = recorder()
        try relaunched.arm(audio)
        try relaunched.startTake()
        try await deliverBlocks(2, to: audio, relaunched)
        try relaunched.stopTake()
        await relaunched.waitForRepair()
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "2026-10-06 Show/Take 02/01 USB 01.wav").path))
    }

    /// A Drive Stem that stalls once, on its first write past `healthyFrames`, until the gate opens, then carries on: a
    /// Drive too slow to keep up for a while, without a race against the clock.
    final class SlowStem: StemSink, @unchecked Sendable {
        let inner: StemWriter
        let healthyFrames: Int
        let gate: StopNeverBlocksTests.Gate
        private var paused = false
        init(_ inner: StemWriter, healthyFrames: Int, gate: StopNeverBlocksTests.Gate) {
            self.inner = inner
            self.healthyFrames = healthyFrames
            self.gate = gate
        }
        var frameCount: UInt64 { inner.frameCount }
        func append(_ samples: UnsafeBufferPointer<Float>) throws {
            if !paused, Int(inner.frameCount) + samples.count > healthyFrames {
                paused = true
                gate.wait()
            }
            try inner.append(samples)
        }
        func commitHeader() throws { try inner.commitHeader() }
        func finalize() throws { try inner.finalize() }
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try inner.setMarkers(markers) }
    }

    @Test("A Drive too slow to keep up drops audio but isn't given up: the Device stands in from the drop, and Repair fills the Drive")
    func slowDrive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        // The stall limit is long, so only the drop (the Drive's 4 s ring overflowing) brings the standby in.
        let recorder = recorder(driveStem: { SlowStem($0, healthyFrames: 4_800, gate: gate) }, stallLimit: .seconds(60))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        // 5 s of audio arrive while the Drive is paused: more than its ring holds. A second at a time, as fast as the
        // standby keeps up with (audio never arrives faster than real time), so only the paused Drive drops.
        let total = 10 * 480 + 240_000
        for second in 0..<5 {
            deliver(48_000, from: 4_800 + second * 48_000, to: audio, block: 480, sample: counting())
            try await Task.sleep(for: .milliseconds(100))
        }
        try await waitUntil { recorder.droppedFrameCount > 0 }
        recorder.checkDestinations()
        // The Drive catches up and carries on.
        gate.open()
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(recorder.lastTakeOutcomes[.drive] == .repaired)
        #expect(try driveSamples(frames: total) == (0..<total).map { counting()($0, 0) }, "the Drive has the whole Take")
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "nothing of the Take is left on the Device")
    }

    @Test("A Drive that pauses past the stall limit and then carries on isn't given up: the Take ends whole on the Drive, nothing on the Device")
    func drivePausesThenResumes() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let recorder = recorder(driveStem: { SlowStem($0, healthyFrames: 4_800, gate: gate) }, stallLimit: .milliseconds(100))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        // The Drive pauses (a healthy one waking up, say) while audio keeps coming, for longer than the stall limit.
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        recorder.checkDestinations()
        // Then it carries on.
        gate.open()
        try await deliverBlocks(9, from: 21 * 480, to: audio, recorder, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(try driveSamples(frames: 14_400) == (0..<14_400).map { counting()($0, 0) }, "the Drive has the whole Take")
        #expect(recorder.lastTakeOutcomes[.drive] != .repairFailed)
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "nothing of the Take is left on the Device")
    }
}

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
        recorder.recordTo = .drive
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
        try await recorder.stopTake()
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
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(CopySummary.ofLastTake(recorder.copies, dropoutCount: recorder.dropoutCount)?.text == "Drive copy: complete")
    }

    @Test("After a Drive only Take the Drive took whole, the Device has no Copy: it reads missing (#618)")
    func deviceMissingAfterDriveTookWhole() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(recorder.copies[.device] == .missing)
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "no Take folder on the Device")
    }

    @Test("After a Drive only Take the Drive took whole, a Marker is renamed in the Drive Copy, with no Device Copy to fail (#618)")
    func renameMarkerAfterDriveTookWhole() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        recorder.addMarker()
        try await deliverBlocks(1, from: 10 * 480, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        let outcome = await recorder.renameLastTakeMarker(at: 0, to: "Intro")

        #expect(outcome.result == .renamed)
        #expect(outcome.renamed == [.drive])
        #expect(outcome.failed.isEmpty)
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).markers.map(\.name) == ["Intro"])
        #expect(recorder.markerEntries.map(\.name) == ["Intro"])
    }

    @Test("After a Drive only Take the Drive took whole, with the Drive gone at rename time, no Copy is renamed and the Drive is named (#618)")
    func renameMarkerDriveGone() async throws {
        final class Flag: @unchecked Sendable { var available = true }
        let flag = Flag()
        let drive = drive
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { flag.available ? DriveAccess(folder: drive) : nil },
            now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        recorder.recordTo = .drive
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        recorder.addMarker()
        try await deliverBlocks(1, from: 10 * 480, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        flag.available = false

        let outcome = await recorder.renameLastTakeMarker(at: 0, to: "Intro")

        #expect(outcome.result == .noCopyUpdated)
        #expect(outcome.renamed.isEmpty)
        #expect(outcome.failed.map(\.copy) == [.drive])
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
        try await recorder.stopTake()
        await recorder.waitForRepair()
    }

    @Test("A Drive only Take with no Drive at record says it records to this iPhone and moves to the Drive later (#550)")
    func noDriveAlert() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        recorder.recordTo = .drive
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())

        let alert = try #require(DestinationAlert.make(copies: recorder.copies))
        #expect(alert.id == "no-drive")
        #expect(alert.text == "No Drive: recording to this iPhone; it moves to the Drive when one is connected.")
        try await recorder.stopTake()
        await recorder.waitForRepair()
    }

    @Test("After a Drive only Take with no Drive at all, the summary says it is on this iPhone until the Drive is back (#550)")
    func summaryNoDrive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        recorder.recordTo = .drive
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
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
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        await recorder.checkDestinations()

        #expect(recorder.copies.isDriveOnly)
        #expect(recorder.copies[.device] == .standingIn)
        #expect(recorder.copies[.drive] == .interrupted)
        try await recorder.stopTake()
        await recorder.waitForRepair()
    }

    @Test("A Drive that fails mid-Take: the Device stands in for the rest, and Repair moves it to the Drive and off the Device")
    func driveFails() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder { FailingStem($0, healthyFrames: 480) }
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        await recorder.checkDestinations()
        try await deliverBlocks(5, from: 10 * 480, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(try driveSamples(frames: 7_200) == (0..<7_200).map { counting()($0, 0) }, "the Drive has the whole Take")
        #expect(recorder.copies[.drive] == .repaired)
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "nothing of the Take is left on the Device")
    }

    @Test("After Repair moves a stand-in to the Drive, a Marker is renamed in the Drive Copy, with no Device Copy to fail (#618)")
    func renameMarkerAfterMove() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder { FailingStem($0, healthyFrames: 480) }
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        recorder.addMarker()
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        await recorder.checkDestinations()
        try await deliverBlocks(5, from: 10 * 480, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(recorder.copies[.device] == .moved)

        let outcome = await recorder.renameLastTakeMarker(at: 0, to: "Intro")

        #expect(outcome.result == .renamed)
        #expect(outcome.renamed == [.drive])
        #expect(outcome.failed.isEmpty)
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).markers.map(\.name) == ["Intro"])
        #expect(recorder.markerEntries.map(\.name) == ["Intro"])
    }

    @Test("After Repair moves a stand-in to the Drive, the summary says it moved from this iPhone (#550)")
    func summaryMoved() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder { FailingStem($0, healthyFrames: 480) }
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        await recorder.checkDestinations()
        try await deliverBlocks(5, from: 10 * 480, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
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
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        for block in 21..<30 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        try await Task.sleep(for: .milliseconds(200))

        let started = ContinuousClock.now
        try await recorder.stopTake()
        // Far below the gate's `hangGuard`; see StopNeverBlocksTests for why not tighter.
        #expect(ContinuousClock.now - started < .seconds(30), "Stop waited on the hung Drive")
        await recorder.waitForRepair()

        // The Device holds the stand-in to the end of the Take, from 2 s before the Drive's last frame (what a pulled
        // Drive may not have made durable; here the start of the Take), and keeps it: the Drive can't be Repaired.
        let deviceTake = try TakeMetadata.read(fromTakeFolder: device.appending(path: take))
        #expect(deviceTake.standIns == [.init(start: 0, end: 14_400)])
        let standIn = device.appending(path: "\(take)/Stand-in 0/01 USB 01.wav")
        #expect(try StemWriter.readSamples(url: standIn, frames: 0..<14_400) == (0..<14_400).map { counting()($0, 0) })
        #expect(try StemFile.inspect(standIn).frameCount == 14_400, "the stand-in's Stem is finalized")
        #expect(recorder.copies[.drive] == .hasGaps)
        #expect(recorder.copies[.device] == .standInKept)
    }

    @Test("A stand-in Stop gave up on is reported abandoned, and its end is what its header committed, not a read of a writer that may still write (#664)")
    func standInAbandonedAtStop() async throws {
        final class Written: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [(TakeMetadata, URL)] = []
            func add(_ metadata: TakeMetadata, _ folder: URL) { lock.withLock { items.append((metadata, folder)) } }
            var all: [(TakeMetadata, URL)] { lock.withLock { items } }
        }
        let written = Written()
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let drive = drive
        let audio = FakeAudioDevice(inputChannelCount: 1)
        // The Drive hangs after 4 800 frames, and then the stand-in's own Stem hangs after 2 400 of its frames.
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                if url.path.hasPrefix(drive.path), resuming == nil { return BlockingStem(real, gate: gate, healthyFrames: 4_800) }
                if url.path.contains("/Stand-in ") { return BlockingStem(real, gate: gate, healthyFrames: 2_400) }
                return real
            }, destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300), driveStallLimit: .milliseconds(100),
            writeAbandoned: { written.add($0, $1) })
        recorder.recordTo = .drive
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        for block in 21..<30 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        try await Task.sleep(for: .milliseconds(200))

        try await recorder.stopTake()
        await recorder.waitForRepair()

        // Stop gave up on the stand-in's writer, so its Device folder is reported abandoned: its Take.json is written
        // off Stop, with an end of what the header committed (the Stem's opening commit, nothing past it).
        let deviceTake = device.appending(path: take)
        let entry = try #require(written.all.first { $0.1.standardizedFileURL == deviceTake.standardizedFileURL })
        #expect(entry.0.standIns == [.init(start: 0, end: 0)])
    }

    @Test("After a Drive given up at Stop, a Marker is renamed in the stand-in kept on the Device too (#622)")
    func renameMarkerStandInKept() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(driveStem: { BlockingStem($0, gate: gate, healthyFrames: 4_800) }, stallLimit: .milliseconds(100))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        recorder.addMarker()
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        for block in 21..<30 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        try await Task.sleep(for: .milliseconds(200))
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(recorder.copies[.device] == .standInKept)
        let standIn = device.appending(path: "\(take)/Stand-in 0/01 USB 01.wav")
        #expect(try cuePoints(standIn).map(\.label) == ["Marker 1"])

        let outcome = await recorder.renameLastTakeMarker(at: 0, to: "Intro")

        #expect(outcome.result == .renamed)
        #expect(Set(outcome.renamed) == [.device, .drive])
        #expect(outcome.failed.isEmpty)
        #expect(try cuePoints(standIn).map(\.label) == ["Intro"])
        #expect(try TakeMetadata.read(fromTakeFolder: device.appending(path: take)).markers.map(\.name) == ["Intro"])
    }

    @Test("After a Drive given up at Stop, a Channel name typed during the Take reaches the stand-in kept on the Device (#622)")
    func nameChannelStandInKept() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(driveStem: { BlockingStem($0, gate: gate, healthyFrames: 4_800) }, stallLimit: .milliseconds(100))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        #expect(recorder.setChannelName("Lead Vocal", forChannel: 1))
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        for block in 21..<30 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        try await Task.sleep(for: .milliseconds(200))
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(recorder.copies[.device] == .standInKept)

        let standIn = device.appending(path: "\(take)/Stand-in 0")
        #expect(!FileManager.default.fileExists(atPath: standIn.appending(path: "01 USB 01.wav").path))
        #expect(try ParsedStem(contentsOf: standIn.appending(path: "01 Lead Vocal.wav")).description == "Lead Vocal")
        let channel = try TakeMetadata.read(fromTakeFolder: device.appending(path: take)).usbChannels[0]
        #expect(channel.name == "Lead Vocal")
        #expect(channel.stemFile == "01 Lead Vocal.wav")
    }

    /// A Drive only Take of 14,400 frames whose Drive hangs after 4,800 and is given up at Stop, so the stand-in
    /// is kept on the Device. The hung Drive Stem waits on `gate`, which the caller opens when done.
    func recordStandInKeptTake(gate: StopNeverBlocksTests.Gate) async throws -> Recorder {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(driveStem: { BlockingStem($0, gate: gate, healthyFrames: 4_800) }, stallLimit: .milliseconds(100))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        for block in 21..<30 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        try await Task.sleep(for: .milliseconds(200))
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(recorder.copies[.device] == .standInKept)
        return recorder
    }

    @Test("After a Drive given up at Stop, deleting a Stem removes the stand-in's file on the Device too (#627)")
    func deleteStemStandInKept() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let recorder = try await recordStandInKeptTake(gate: gate)
        try recorder.endShow()
        let standIn = device.appending(path: "\(take)/Stand-in 0/01 USB 01.wav")
        #expect(FileManager.default.fileExists(atPath: standIn.path))

        let outcome = recorder.deleteChannel(1, inTake: 1, ofShow: "2026-10-06 Show", from: [.device, .drive])

        #expect(outcome.deleted == [.device, .drive])
        #expect(!FileManager.default.fileExists(atPath: standIn.path), "the stand-in's Stem is gone")
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "\(take)/01 USB 01.wav").path))
        #expect(try TakeMetadata.read(fromTakeFolder: device.appending(path: take)).usbChannels.isEmpty)
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).usbChannels.isEmpty)
    }

    @Test("After a Drive given up at Stop, the Copy check fails for the Drive's Gaps and the stand-in, not for reading the Device's Stems (#627)")
    func copyCheckStandInKept() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let recorder = try await recordStandInKeptTake(gate: gate)

        let result = CopyCheck.verify(show: "2026-10-06 Show", device: device, drive: drive)

        #expect(result == .failed(["Take 01 on the Drive still has Gaps.", "Take 01 still has audio only on the Device."]))
    }

    @Test("After a Drive given up at Stop, its stand-in stays on the Device and the summary says so (#550)")
    func summaryStandInStays() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(driveStem: { BlockingStem($0, gate: gate, healthyFrames: 4_800) }, stallLimit: .milliseconds(100))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        for block in 21..<30 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        try await Task.sleep(for: .milliseconds(200))
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(CopySummary.ofLastTake(recorder.copies, dropoutCount: 0)?.text == "On this iPhone until the Drive is back")
    }

    @Test("After a relaunch the next Take gets a new number, though the Device has no folder for the last one")
    func takeNumberSurvivesRelaunch() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let first = recorder()
        try first.arm(audio)
        try first.startTake()
        try await deliverBlocks(2, to: audio, first)
        try await first.stopTake()
        await first.waitForRepair()
        first.disarm()

        let relaunched = recorder()
        try relaunched.arm(audio)
        try relaunched.startTake()
        try await deliverBlocks(2, to: audio, relaunched)
        try await relaunched.stopTake()
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
        await recorder.checkDestinations()
        // The Drive catches up and carries on.
        gate.open()
        try await waitUntil { recorder.bufferedFrameCount == 0 }
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(recorder.copies[.drive] == .repaired)
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
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        // Then it carries on.
        gate.open()
        try await deliverBlocks(9, from: 21 * 480, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(try driveSamples(frames: 14_400) == (0..<14_400).map { counting()($0, 0) }, "the Drive has the whole Take")
        #expect(recorder.copies[.drive] == .complete)
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "nothing of the Take is left on the Device")
    }

    @Test("After a Drive that paused and caught up, its spare stand-in is gone and the summary says the Drive is complete (#550)")
    func summarySpareStandIn() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let recorder = recorder(driveStem: { SlowStem($0, healthyFrames: 4_800, gate: gate) }, stallLimit: .milliseconds(100))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        gate.open()
        try await deliverBlocks(9, from: 21 * 480, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(CopySummary.ofLastTake(recorder.copies, dropoutCount: 0)?.text == "Drive copy: complete")
    }

    /// A Drive only Take whose Drive paused past the stall limit (the Device stood in) and caught up, so the Take has
    /// no Gaps and the stand-in is a spare. Adds a Marker early on.
    func spareStandInTake() async throws -> Recorder {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let recorder = recorder(driveStem: { SlowStem($0, healthyFrames: 4_800, gate: gate) }, stallLimit: .milliseconds(100))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        recorder.addMarker()
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        gate.open()
        try await deliverBlocks(9, from: 21 * 480, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()
        return recorder
    }

    @Test("After a Drive that paused and caught up, the spare stand-in leaves no Device Copy: it reads missing (#621)")
    func spareStandInDeviceMissing() async throws {
        let recorder = try await spareStandInTake()

        #expect(recorder.copies[.device] == .missing)
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "no Take folder on the Device")
    }

    @Test("After a Drive that paused and caught up, a Marker is renamed in the Drive Copy, with no Device Copy to fail (#621)")
    func renameMarkerAfterSpareStandIn() async throws {
        let recorder = try await spareStandInTake()

        let outcome = await recorder.renameLastTakeMarker(at: 0, to: "Intro")

        #expect(outcome.result == .renamed)
        #expect(outcome.renamed == [.drive])
        #expect(outcome.failed.isEmpty)
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).markers.map(\.name) == ["Intro"])
        #expect(recorder.markerEntries.map(\.name) == ["Intro"])
    }

    /// A Drive only Show of two Takes (#625): Take 01 the Drive took whole (nothing on the Device), Take 02 on a Drive
    /// that hung, so its stand-in (0..<14 400) is kept on the Device and the Drive's Stems stop short.
    func recordWholeThenKeptStandIn(gate: StopNeverBlocksTests.Gate) async throws -> Recorder {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(driveStem: { BlockingStem($0, gate: gate, healthyFrames: 4_800) }, stallLimit: .milliseconds(100))
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        await recorder.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await recorder.checkDestinations()
        for block in 21..<30 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        try await Task.sleep(for: .milliseconds(200))
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(recorder.copies[.device] == .standInKept)
        return recorder
    }

    @Test("A Drive only Show's recorded time counts the Takes on the Drive and a kept stand-in's whole length (#625)")
    func recordedSecondsDriveOnly() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let recorder = try await recordWholeThenKeptStandIn(gate: gate)

        let show = try #require(recorder.currentShow)
        // Take 01: 4 800 frames on the Drive; Take 02: its stand-in's 14 400 frames, at 48 kHz.
        #expect(abs(try show.recordedSeconds(leavingOut: nil) - 0.4) < 0.000_1)
        #expect(abs(try show.recordedSeconds(leavingOut: 2) - 0.1) < 0.000_1)
    }

    @Test("A Drive only Show lists every Take, on the Drive or kept as a stand-in on the Device, with its whole length (#625)")
    func showListDriveOnly() async throws {
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        _ = try await recordWholeThenKeptStandIn(gate: gate)

        let show = try #require(ShowList.read(device: device, drive: drive).first)
        #expect(show.takeCount == 2)
        // Both Takes start at the same (fixed) clock time; the longer is Take 02's 14 400 frames.
        #expect(abs(show.duration - 0.3) < 0.000_1)
    }

    @Test("Relaunched into an open Drive only Show, the record screen's total reads the Drive's Takes under Drive access (#625)")
    func showTotalAfterRelaunch() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let first = recorder()
        try first.arm(audio)
        try first.startTake()
        try await deliverBlocks(10, to: audio, first)
        try await first.stopTake()
        await first.waitForRepair()
        first.disarm()

        let relaunched = recorder()
        #expect(relaunched.currentShow?.driveFolder == nil, "a relaunch doesn't know the Drive until the next record press")
        // Take 01: 4 800 frames, only on the Drive.
        #expect(abs((relaunched.showRecordedSeconds(leavingOut: nil) ?? 0) - 0.1) < 0.000_1)
    }

    /// Removes the Show's report and project in both Copies, so the next launch must write them again.
    func removeReports() {
        for parent in [device, drive] {
            let folder = parent.appending(path: "2026-10-06 Show")
            try? FileManager.default.removeItem(at: folder.appending(path: "Report.html"))
            try? FileManager.default.removeItem(at: folder.appending(path: "2026-10-06 Show.RPP"))
        }
    }

    /// The next launch over a Take a crash cut off (the crashed recorder is left running, so its files are what a crash
    /// mid-Take leaves), once its Repair is done.
    func launch(withDrive: Bool = true) async throws -> Recorder {
        let next = withDrive
            ? recorder()
            : Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try await waitUntil { !next.isRepairing }
        await next.waitForRepair()
        return next
    }

    /// A Drive only Take whose Drive failed and the Device stood in, cut off mid-Take. Returns the crashed recorder.
    func crashAfterStandIn() async throws -> Recorder {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let crashed = recorder { FailingStem($0, healthyFrames: 480) }
        try crashed.arm(audio)
        try crashed.startTake()
        try await deliverBlocks(10, to: audio, crashed, sample: counting())
        try await waitUntil { crashed.copies[.drive] == .interrupted }
        await crashed.checkDestinations()
        try await deliverBlocks(5, from: 10 * 480, to: audio, crashed, sample: counting())
        try await waitUntil { crashed.bufferedFrameCount == 0 }
        removeReports()
        return crashed
    }

    @Test("A Drive only Take cut off before any stand-in is finished at the next launch, with nothing left on the Device (#626)")
    func cutOffWithoutStandIn() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let crashed = recorder()
        try crashed.arm(audio)
        try crashed.startTake()
        try await deliverBlocks(10, to: audio, crashed, sample: counting())
        try await waitUntil { crashed.bufferedFrameCount == 0 }
        removeReports()

        let next = try await launch()

        #expect(try StemFile.inspect(drive.appending(path: "\(take)/01 USB 01.wav")).frameCount == 4_800, "the header covers the audio on disk")
        for parent in [device, drive] {
            let folder = parent.appending(path: "2026-10-06 Show")
            #expect(ShowFile.read(from: folder)?.lastTakeEndedAt != nil, "\(parent.lastPathComponent) Show knows the Take ended")
        }
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "2026-10-06 Show/Report.html").path))
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: take).path), "no Take folder on the Device")
        #expect(next.copies[.device] == .missing)
    }

    @Test("A Drive only Take cut off after its stand-in started is finished at the next launch: Repair fills the Drive from the stand-in, which stays (#626)")
    func cutOffAfterStandIn() async throws {
        let crashed = try await crashAfterStandIn()

        let next = try await launch()

        #expect(try driveSamples(frames: 7_200) == (0..<7_200).map { counting()($0, 0) }, "the Drive has the whole Take")
        #expect(try StemFile.inspect(drive.appending(path: "\(take)/01 USB 01.wav")).frameCount == 7_200, "the Take ends where the stand-in does")
        let metadata = try TakeMetadata.read(fromTakeFolder: drive.appending(path: take))
        #expect(!metadata.gaps.contains { $0.copy == .device }, "no Device Gap")
        #expect(!metadata.repairs.contains { $0.outcome == .failed }, "\(metadata.repairs)")
        #expect(next.copies[.drive] == .repaired)
        #expect(next.copies[.device] == .standInKept, "a cut-off stand-in is never removed at launch")
        try expectStandInKept()
        #expect(ShowFile.read(from: drive.appending(path: "2026-10-06 Show"))?.lastTakeEndedAt != nil)
        _ = crashed
    }

    /// A Drive only Take whose Drive paused past the stall limit, so the Device stood in, and then caught up, cut off
    /// mid-Take. Returns the crashed recorder.
    func crashAfterSpareStandIn() async throws -> Recorder {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let gate = StopNeverBlocksTests.Gate()
        defer { gate.open() }
        let crashed = recorder(driveStem: { SlowStem($0, healthyFrames: 4_800, gate: gate) }, stallLimit: .milliseconds(100))
        try crashed.arm(audio)
        try crashed.startTake()
        try await deliverBlocks(10, to: audio, crashed, sample: counting())
        for block in 10..<20 { deliver(480, from: block * 480, to: audio, sample: counting()) }
        await crashed.checkDestinations()
        try await Task.sleep(for: .milliseconds(250))
        deliver(480, from: 20 * 480, to: audio, sample: counting())
        await crashed.checkDestinations()
        gate.open()
        try await deliverBlocks(9, from: 21 * 480, to: audio, crashed, sample: counting())
        try await waitUntil { crashed.bufferedFrameCount == 0 }
        removeReports()
        return crashed
    }

    /// Where the cut-off Take's stand-in starts, from the Device's Take.json.
    func standInStart() throws -> Int {
        try #require(TakeMetadata.read(fromTakeFolder: device.appending(path: take)).standIns?.first).start
    }

    /// The cut-off Take's stand-in is still on the Device: its folder and Stems, listed in both Copies' Take.json.
    func expectStandInKept(sourceLocation: SourceLocation = #_sourceLocation) throws {
        let start = try standInStart()
        let folder = device.appending(path: "\(take)/\(TakeMetadata.StandIn(start: start, end: start).folderName)")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "01 USB 01.wav").path), "the stand-in's Stem is kept", sourceLocation: sourceLocation)
        #expect(try TakeMetadata.read(fromTakeFolder: drive.appending(path: take)).standIns?.first?.start == start, sourceLocation: sourceLocation)
    }

    @Test("A Drive only Take cut off after a stand-in the Drive caught up with keeps the stand-in at the next launch (#626)")
    func cutOffAfterSpareStandIn() async throws {
        let crashed = try await crashAfterSpareStandIn()

        _ = try await launch()

        #expect(try driveSamples(frames: 14_400) == (0..<14_400).map { counting()($0, 0) }, "the Drive has the whole Take")
        try expectStandInKept()
        _ = crashed
    }

    @Test("A cut-off Drive only Take whose Drive wrote silence over the stand-in's stretch, with no Gap in Take.json yet, keeps the stand-in (#626)")
    func cutOffDriveSilenceOverStandIn() async throws {
        let crashed = try await crashAfterSpareStandIn()
        // What a Drive whose ring overflowed writes (silence for the dropped frames) before its Gap reaches Take.json.
        let start = try standInStart()
        try silence(drive.appending(path: "\(take)/01 USB 01.wav"), from: start, frames: 14_400 - start)

        _ = try await launch()

        // The audio is safe on the Device; the Drive keeps the silence until a kept stand-in is moved (#630).
        try expectStandInKept()
        _ = crashed
    }

    @Test("A cut-off Drive only Take whose standby dropped audio the Drive has leaves the Drive's audio alone, and the stand-in stays (#626)")
    func cutOffStandInSilenceOverDrive() async throws {
        let crashed = try await crashAfterSpareStandIn()
        let start = try standInStart()
        let standIn = device.appending(path: "\(take)/\(TakeMetadata.StandIn(start: start, end: start).folderName)/01 USB 01.wav")
        try silence(standIn, from: 0, frames: 14_400 - start)

        _ = try await launch()

        #expect(try driveSamples(frames: 14_400) == (0..<14_400).map { counting()($0, 0) }, "the Drive's audio is unchanged")
        try expectStandInKept()
        _ = crashed
    }

    /// Writes `frames` of silence into the Stem at `url` from `frame` (relative to the Stem), leaving its header alone.
    func silence(_ url: URL, from frame: Int, frames: Int) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: UInt64(StemWriter.dataStart + frame * StemWriter.bytesPerSample))
        try handle.write(contentsOf: Data(count: frames * StemWriter.bytesPerSample))
        try handle.close()
    }

    @Test("A Drive only Take cut off after its stand-in started, with no Drive at the next launch, keeps its finished stand-in on the Device (#626)")
    func cutOffAfterStandInNoDrive() async throws {
        let crashed = try await crashAfterStandIn()
        let start = try standInStart()

        _ = try await launch(withDrive: false)

        let metadata = try TakeMetadata.read(fromTakeFolder: device.appending(path: take))
        #expect(metadata.standIns == [.init(start: start, end: 7_200)])
        let stem = device.appending(path: "\(take)/\(TakeMetadata.StandIn(start: start, end: 7_200).folderName)/01 USB 01.wav")
        #expect(try StemFile.inspect(stem).frameCount == UInt64(7_200 - start), "the stand-in's header covers its audio on disk")
        #expect(ShowFile.read(from: device.appending(path: "2026-10-06 Show"))?.lastTakeEndedAt != nil, "the Take is noted ended")
        _ = crashed
    }

    /// The `driveOnly` field of the Take.json in `parent`'s copy of the Take, read raw; nil when it isn't there.
    func driveOnlyField(in parent: URL) throws -> Bool? {
        let data = try Data(contentsOf: parent.appending(path: "\(take)/Take.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])["driveOnly"] as? Bool
    }

    @Test("A Drive only Take's Take.json on the Drive says it is Drive only (#630)")
    func takeFileSaysDriveOnly() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())

        #expect(try driveOnlyField(in: drive) == true)
        try await recorder.stopTake()
        await recorder.waitForRepair()
    }

    @Test("A Drive only Take with no Drive at record says it is Drive only in the Device's Take.json, from the press (#630)")
    func takeFileSaysDriveOnlyWithNoDrive() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        recorder.recordTo = .drive
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())

        #expect(try driveOnlyField(in: device) == true, "while the Take runs")
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(try driveOnlyField(in: device) == true, "after Stop")
    }

    @Test("An ordinary Take's Take.json has no driveOnly field in either Copy (#630)")
    func ordinaryTakeFileHasNoDriveOnly() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        recorder.recordTo = .both
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(try driveOnlyField(in: device) == nil)
        #expect(try driveOnlyField(in: drive) == nil)
    }

    @Test("With the Device chosen, a Take with a Drive connected writes no Drive Copy: Device only (#805)")
    func deviceChosenWritesNoDriveCopy() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder()
        recorder.recordTo = .device
        try recorder.arm(audio)
        try recorder.startTake()
        try await deliverBlocks(2, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(FileManager.default.fileExists(atPath: device.appending(path: "\(take)/01 USB 01.wav").path))
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: take).path), "no Take folder on the Drive")
        #expect(try driveOnlyField(in: device) == nil)
    }

    @Test("After a launch that finished a cut-off Drive only Take with a stand-in, the summary speaks of Drive only (#630)")
    func cutOffSummaryIsDriveOnly() async throws {
        let crashed = try await crashAfterStandIn()

        let next = try await launch()

        #expect(next.copies.isDriveOnly)
        #expect(CopySummary.ofLastTake(next.copies, dropoutCount: 0)?.text == "On this iPhone until the Drive is back")
        _ = crashed
    }

    /// A Take cut off mid-Take with no stand-in: Drive only or not, with the Drive at the press or none. Returns the
    /// crashed recorder.
    func crashMidTake(driveOnly: Bool, withDrive: Bool) async throws -> Recorder {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let crashed = Recorder(
            deviceFolder: device, driveFolder: { withDrive ? DriveAccess(folder: drive) : nil }, now: { RecordingTakeTests.showDay },
            destinationCheckInterval: nil)
        crashed.recordTo = driveOnly ? .drive : .both
        try crashed.arm(audio)
        try crashed.startTake()
        try await deliverBlocks(10, to: audio, crashed, sample: counting())
        try await waitUntil { crashed.bufferedFrameCount == 0 }
        removeReports()
        return crashed
    }

    @Test("After a launch that finished a cut-off Drive only Take the Drive took whole, the Copies say Drive only (#630)")
    func cutOffDriveWholeIsDriveOnly() async throws {
        let crashed = try await crashMidTake(driveOnly: true, withDrive: true)

        let next = try await launch()

        #expect(next.copies.isDriveOnly)
        _ = crashed
    }

    @Test("After a launch that finished a cut-off Drive only Take recorded with no Drive, the Copies say Drive only (#630)")
    func cutOffNoDriveIsDriveOnly() async throws {
        let crashed = try await crashMidTake(driveOnly: true, withDrive: false)

        let next = try await launch()

        #expect(next.copies.isDriveOnly)
        _ = crashed
    }

    @Test("After a launch that finished a cut-off ordinary Take, the Copies don't say Drive only (#630)")
    func cutOffOrdinaryIsNotDriveOnly() async throws {
        let crashed = try await crashMidTake(driveOnly: false, withDrive: true)

        let next = try await launch()

        #expect(!next.copies.isDriveOnly)
        _ = crashed
    }
}

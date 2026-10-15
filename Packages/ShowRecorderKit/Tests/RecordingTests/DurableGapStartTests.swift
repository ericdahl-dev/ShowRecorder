import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Testing

/// A Stem on a Drive that is pulled after `healthyFrames`, or at its `failingCommit`th header commit (#595): what was
/// appended since its last commit never made it whole, so past that commit the file holds only garbage.
final class LossyStem: StemSink, @unchecked Sendable {
    struct Pulled: Error {}
    private let real: StemWriter
    private let healthyFrames: Int
    private let failingCommit: Int?
    private var commits = 0
    private var pending: [Float] = []
    private var pulled = false
    var frameCount: UInt64 { real.frameCount + UInt64(pending.count) }
    var committedFrameCount: UInt64 { real.committedFrameCount }

    init(_ real: StemWriter, healthyFrames: Int = .max, failingCommit: Int? = nil) {
        self.real = real
        self.healthyFrames = healthyFrames
        self.failingCommit = failingCommit
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws {
        if pulled { throw Pulled() }
        if Int(frameCount) + samples.count > healthyFrames { try pull() }
        pending += samples
    }
    func commitHeader() throws {
        if pulled { throw Pulled() }
        commits += 1
        if commits == failingCommit { try pull() }
        try pending.withUnsafeBufferPointer { try real.append($0) }
        pending = []
        try real.commitHeader()
    }
    func finalize() throws { try real.finalize() }
    @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try real.setMarkers(markers) }

    /// The Drive goes: in place of the uncommitted audio the file is left with garbage, never committed.
    private func pull() throws -> Never {
        pulled = true
        let garbage = [Float](repeating: 0.5, count: pending.count)
        try garbage.withUnsafeBufferPointer { try real.append($0) }
        pending = []
        throw Pulled()
    }
}

extension GapTests {
    final class Lossy: @unchecked Sendable {
        var stems: [LossyStem] = []
        var stem: LossyStem? { stems.first }
        var driveResumes: [UInt64?] = []
    }

    /// A recorder whose first Drive Stems are `LossyStem`s; `failingCommit` gives each Stem file's, if any.
    func lossyDriveRecorder(
        _ lossy: Lossy, healthyFrames: Int = .max, failingCommit: @escaping @Sendable (String) -> Int? = { _ in nil }
    ) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                guard url.path.contains("/Drive/") else { return real }
                lossy.driveResumes.append(resuming)
                guard resuming == nil else { return real }
                let stem = LossyStem(real, healthyFrames: healthyFrames, failingCommit: failingCommit(url.lastPathComponent))
                lossy.stems.append(stem)
                return stem
            }, destinationCheckInterval: nil)
    }

    /// Samples in the Drive's Stem file `name`, from its size on disk.
    func driveSamplesOnDisk(_ name: String) throws -> UInt64 {
        let url = drive.appending(path: "2026-10-06 Show/Take 01/\(name)")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! UInt64
        return (size - UInt64(StemWriter.dataStart)) / 3
    }

    @Test("A pulled Drive that comes back resumes from its last commit, and Repair fills everything it lost (#595)")
    func rejoinResumesFromLastCommit() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let lossy = Lossy()
        let recorder = lossyDriveRecorder(lossy, healthyFrames: 120_000)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliver(144_000, to: audio, recorder, block: 4800, sample: counting())
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        let committed = try #require(lossy.stem).committedFrameCount
        let appended = try #require(lossy.stem).frameCount
        #expect(committed > 0 && committed < appended)
        // Past the commit the file holds garbage, which the rejoin must cut off.
        #expect(try driveSamplesOnDisk("01 USB 01.wav") >= appended)

        try await waitUntil { recorder.checkDestinations(); return lossy.driveResumes.count == 2 }
        try await deliver(4800, from: 144_000, to: audio, recorder, block: 480, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(lossy.driveResumes.last == committed)
        let gaps = try decodedTake(device).gaps
        #expect(gaps.map(\.copy) == [.drive])
        #expect(gaps.first?.start == Int(committed))
        let deviceFiles = try takeFiles(in: device)
        let driveFiles = try takeFiles(in: drive)
        for (name, data) in deviceFiles { #expect(driveFiles[name] == data, "\(name) differs between the Copies") }
    }

    @Test("A pulled Drive that never comes back is missing everything from its last commit, and Repair fills it (#595)")
    func trailingGapStartsAtLastCommit() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let lossy = Lossy()
        let recorder = lossyDriveRecorder(lossy, healthyFrames: 120_000)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliver(144_000, to: audio, recorder, block: 4800, sample: counting())
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        let committed = try #require(lossy.stem).committedFrameCount
        #expect(committed > 0)
        try recorder.stopTake()
        await recorder.waitForRepair()

        let gaps = try decodedTake(device).gaps
        #expect(gaps.map(\.copy) == [.drive])
        #expect(gaps.first?.start == Int(committed))
        let deviceFiles = try takeFiles(in: device)
        let driveFiles = try takeFiles(in: drive)
        for (name, data) in deviceFiles { #expect(driveFiles[name] == data, "\(name) differs between the Copies") }
    }

    @Test("A Drive pulled while committing, after one Stem committed and before the other, resumes each Stem at its own commit (#595)")
    func stemsResumeAtTheirOwnCommits() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let lossy = Lossy()
        let recorder = lossyDriveRecorder(lossy, failingCommit: { $0 == "02 USB 02.wav" ? 2 : nil })
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliver(144_000, to: audio, recorder, block: 4800, sample: counting(channelStep: 100_000))
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        try #require(lossy.stems.count == 2)
        let committed = lossy.stems.map(\.committedFrameCount)
        #expect(committed[0] > committed[1])

        try await waitUntil { recorder.checkDestinations(); return lossy.driveResumes.count == 4 }
        try await deliver(4800, from: 144_000, to: audio, recorder, block: 480, sample: counting(channelStep: 100_000))
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(Array(lossy.driveResumes.suffix(2)) == committed.map { Optional($0) })
        let gaps = try decodedTake(device).gaps
        #expect(gaps.map(\.copy) == [.drive])
        #expect(gaps.first?.start == Int(committed.min()!))
        let deviceFiles = try takeFiles(in: device)
        let driveFiles = try takeFiles(in: drive)
        for (name, data) in deviceFiles { #expect(driveFiles[name] == data, "\(name) differs between the Copies") }
    }

    @Test("A Device whose write fails keeps what it wrote past its last commit: its Gap starts where it stopped (#595)")
    func deviceGapStartsWhereItStopped() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        final class Holder: @unchecked Sendable { var stem: KeepingStem? }
        let keeping = Holder()
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                guard url.path.contains("/Device/") else { return real }
                let stem = KeepingStem(real, healthyFrames: 120_000)
                keeping.stem = stem
                return stem
            }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliver(144_000, to: audio, recorder, block: 4800, sample: counting())
        try await waitUntil { recorder.copies[.device] == .interrupted }
        let stem = try #require(keeping.stem)
        #expect(stem.committedFrameCount < stem.frameCount)
        try recorder.stopTake()
        await recorder.waitForRepair()

        let gaps = try decodedTake(drive).gaps
        #expect(gaps.map(\.copy) == [.device])
        #expect(gaps.first?.start == Int(stem.frameCount))
        let deviceFiles = try takeFiles(in: device)
        let driveFiles = try takeFiles(in: drive)
        for (name, data) in driveFiles { #expect(deviceFiles[name] == data, "\(name) differs between the Copies") }
    }
}

/// A Device Stem whose writes fail after `healthyFrames` while everything it wrote stays on disk, committed or not.
final class KeepingStem: StemSink, @unchecked Sendable {
    struct Failure: Error {}
    private let real: StemWriter
    private let healthyFrames: Int
    var frameCount: UInt64 { real.frameCount }
    var committedFrameCount: UInt64 { real.committedFrameCount }

    init(_ real: StemWriter, healthyFrames: Int) {
        self.real = real
        self.healthyFrames = healthyFrames
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws {
        if Int(real.frameCount) + samples.count > healthyFrames { throw Failure() }
        try real.append(samples)
    }
    func commitHeader() throws { try real.commitHeader() }
    func finalize() throws { try real.finalize() }
    @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try real.setMarkers(markers) }
}

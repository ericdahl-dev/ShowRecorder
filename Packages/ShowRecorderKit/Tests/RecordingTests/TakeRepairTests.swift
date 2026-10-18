import BroadcastWave
import Destinations
import Foundation
import MixerLink
@testable import Recording
import Testing

/// Repair on its own: no recorder, no recorded Takes.
@MainActor
@Suite("Repair")
struct TakeRepairTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "TakeRepairTests-\(UUID().uuidString)")
    }

    /// What the stand-in Repair was asked, and a way to hold it until a test lets it go.
    final class Runner: @unchecked Sendable {
        private let lock = NSLock()
        private var _skips: [Set<DestinationKind>] = []
        private var _takes: [Int] = []
        let gate = DispatchSemaphore(value: 0)
        var held = false

        var skips: [Set<DestinationKind>] { lock.withLock { _skips } }
        var takes: [Int] { lock.withLock { _takes } }

        func run(copies: [TakeRepair.Copy], metadata: TakeMetadata, skip: Set<DestinationKind>) -> [TakeMetadata.Repair] {
            lock.withLock { _skips.append(skip); _takes.append(metadata.take) }
            if held && metadata.take == 1 { gate.wait() }
            return metadata.gaps.filter { !skip.contains($0.copy) }.map { .init(copy: $0.copy, start: $0.start, end: $0.end, outcome: .repaired) }
        }
    }

    func folders(_ name: String, deviceFrames: Int = 0, driveFrames: Int = 0) throws -> [DestinationKind: URL] {
        try Dictionary(uniqueKeysWithValues: [(DestinationKind.device, "Device", deviceFrames), (.drive, "Drive", driveFrames)].map { kind, copy, frames in
            let folder = root.appending(path: "\(name)/\(copy)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: RecordingTakeTests.showDay)
            let stem = try StemWriter.open(url: folder.appending(path: "01 USB 01.wav"), info: info, resumingAt: nil)
            try [Float](repeating: 0.1, count: frames).withUnsafeBufferPointer { try stem.append($0) }
            try stem.finalize()
            return (kind, folder)
        })
    }

    func metadata(take: Int, gaps: [TakeMetadata.Gap]) -> TakeMetadata {
        var metadata = TakeMetadata(
            show: "Show", take: take, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        metadata.gaps = gaps
        return metadata
    }

    let driveGap = TakeMetadata.Gap(copy: .drive, start: 480, end: 4800)

    @Test("A Take with no Gaps is complete at once, releases its access and runs nothing")
    func noGaps() throws {
        let runner = Runner()
        let queue = TakeRepair(freeSpace: { _ in .max }, run: runner.run)
        let released = ReleaseCounter()
        queue.enqueue(metadata(take: 1, gaps: []), folders: try folders("a"), holding: DriveAccess(folder: root, stop: { released.increment() }))

        #expect(queue.outcomes == [.device: .complete, .drive: .complete])
        #expect(!queue.isRunning)
        #expect(released.count == 1)
        #expect(runner.takes.isEmpty)
    }

    @Test("A Take with no Gaps holds the Drive's access until the Take.json of a Copy Stop gave up on is written (#652)", .timeLimit(.minutes(3)))
    func noGapsAbandonedHoldsAccess() async throws {
        let released = ReleaseCounter()
        let seen = ReleaseCounter()
        let queue = TakeRepair(freeSpace: { _ in .max }, writeAbandoned: { _, _ in if released.count > 0 { seen.increment() } })
        queue.enqueue(
            metadata(take: 1, gaps: []), folders: try folders("a"), holding: DriveAccess(folder: root, stop: { released.increment() }),
            abandoned: [.drive])
        await queue.wait()

        #expect(seen.count == 0, "the access was released before the abandoned Copy's Take.json was written")
        #expect(released.count == 1)
    }

    @Test("A Take with Gaps shows them as unrepaired until Repair has run, then holds its access to the end")
    func repairsAndReleases() async throws {
        let runner = Runner()
        let queue = TakeRepair(freeSpace: { _ in .max }, run: runner.run)
        let released = ReleaseCounter()
        var changes = 0
        queue.onChange = { changes += 1 }
        queue.enqueue(metadata(take: 1, gaps: [driveGap]), folders: try folders("a", deviceFrames: 4800, driveFrames: 480), holding: DriveAccess(folder: root, stop: { released.increment() }))

        #expect(queue.outcomes == [.device: .complete, .drive: .hasGaps])
        #expect(queue.isRunning)
        #expect(released.count == 0)

        await queue.wait()
        #expect(queue.outcomes == [.device: .complete, .drive: .repaired])
        #expect(!queue.isRunning)
        #expect(released.count == 1)
        #expect(changes >= 3)
    }

    @Test("Only the latest Take's Repair sets the outcome, even when an earlier Take's finishes after the later one is queued")
    func latestTakeWins() async throws {
        let runner = Runner()
        runner.held = true
        let queue = TakeRepair(freeSpace: { _ in .max }, run: runner.run)
        var seenWhenFirstDone: [DestinationKind: CopyOutcome]?
        queue.jobDone = { _ in if seenWhenFirstDone == nil { seenWhenFirstDone = queue.outcomes } }

        queue.enqueue(metadata(take: 1, gaps: [driveGap]), folders: try folders("a", deviceFrames: 4800, driveFrames: 480), holding: nil)
        queue.enqueue(metadata(take: 2, gaps: [driveGap]), folders: try folders("b", deviceFrames: 4800, driveFrames: 480), holding: nil)
        runner.gate.signal()
        await queue.wait()

        // When Take 1's Repair finished, Take 2 had been queued: its Gaps showed, not Take 1's result.
        #expect(seenWhenFirstDone == [.device: .complete, .drive: .hasGaps])
        #expect(runner.takes == [1, 2])
        #expect(queue.outcomes == [.device: .complete, .drive: .repaired])
        #expect(!queue.isRunning)
    }

    @Test("Repair is skipped for a Copy it would fill past the space reserve")
    func reserveKept() async throws {
        let runner = Runner()
        let reserve = SpaceReserve(channelCount: 1, sampleRate: 48_000)
        let drive = root.appending(path: "a/Drive").path
        // The Drive Copy stopped at 480 frames and would grow by 4320 frames of 24-bit audio.
        let extra = Int64(4320 * StemWriter.bytesPerSample)
        let queue = TakeRepair(freeSpace: { $0.path == drive ? reserve.bytes + extra - 1 : .max }, run: runner.run)

        queue.enqueue(metadata(take: 1, gaps: [driveGap]), folders: try folders("a", deviceFrames: 4800, driveFrames: 480), holding: nil)
        await queue.wait()
        #expect(runner.skips == [[.drive]])
        #expect(queue.outcomes[.drive] == .hasGaps)

        // One byte more room and it is repaired.
        let roomy = TakeRepair(freeSpace: { $0.path == drive ? reserve.bytes + extra : .max }, run: runner.run)
        roomy.enqueue(metadata(take: 2, gaps: [driveGap]), folders: try folders("b", deviceFrames: 4800, driveFrames: 480), holding: nil)
        await roomy.wait()
        #expect(runner.skips.last == [])
    }

    // MARK: - Drive only (#196, ADR 0006)

    @Test("Drive only: Repair fills the Drive's Gap from the Device stand-in, then removes the Take from the Device")
    func standInMovedToDrive() async throws {
        let take = (0..<10_000).map { Float($0 % 100) / 200 }
        let stem = "01 USB 01.wav"
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        func write(_ samples: [Float], to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let writer = try StemWriter.open(url: url, info: info, resumingAt: nil)
            try samples.withUnsafeBufferPointer { try writer.append($0) }
            try writer.finalize()
        }
        let device = root.appending(path: "Device/Take 01")
        let drive = root.appending(path: "Drive/Take 01")
        // The Drive was lost for Take frames 3,000 to 7,000: silence there on the Drive, and only those frames on the Device.
        try write(Array(take[0..<3_000]) + [Float](repeating: 0, count: 4_000) + Array(take[7_000...]), to: drive.appending(path: stem))
        var metadata = metadata(take: 1, gaps: [.init(copy: .drive, start: 3_000, end: 7_000)])
        metadata.standIns = [.init(start: 3_000, end: 7_000)]
        let standIn = device.appending(path: metadata.standIns![0].folderName)
        try write(Array(take[3_000..<7_000]), to: standIn.appending(path: stem))
        try metadata.write(to: device)
        try metadata.write(to: drive)

        let queue = TakeRepair(freeSpace: { _ in .max })
        queue.enqueue(metadata, folders: [.device: device, .drive: drive], holding: nil)
        await queue.wait()

        let whole = root.appending(path: "whole.wav")
        try write(take, to: whole)
        #expect(try StemWriter.readSamples(url: drive.appending(path: stem), frames: 0..<10_000) == StemWriter.readSamples(url: whole, frames: 0..<10_000))
        #expect(queue.outcomes[.drive] == .repaired)
        #expect(!FileManager.default.fileExists(atPath: device.path), "nothing of the Take is left on the Device")
        #expect(try TakeMetadata.read(fromTakeFolder: drive).outcome(ofCopy: .drive) == .repaired)
        #expect(try TakeMetadata.read(fromTakeFolder: drive).standIns == nil, "the moved stand-ins are no longer named")
    }

    @Test("Drive only: a Gap the stand-ins don't fully cover is Repair failed, and the stand-in stays on the Device")
    func standInKeptWhenIncomplete() async throws {
        let stem = "01 USB 01.wav"
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        func write(_ frames: Int, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let writer = try StemWriter.open(url: url, info: info, resumingAt: nil)
            try [Float](repeating: 0.1, count: frames).withUnsafeBufferPointer { try writer.append($0) }
            try writer.finalize()
        }
        let device = root.appending(path: "Device/Take 01")
        let drive = root.appending(path: "Drive/Take 01")
        try write(10_000, to: drive.appending(path: stem))
        // The Drive missed 3,000 to 7,000, but the Device only got 3,000 to 5,000 (it filled up).
        var metadata = metadata(take: 1, gaps: [.init(copy: .drive, start: 3_000, end: 7_000)])
        metadata.standIns = [.init(start: 3_000, end: 5_000)]
        try write(2_000, to: device.appending(path: metadata.standIns![0].folderName).appending(path: stem))
        try metadata.write(to: device)

        let queue = TakeRepair(freeSpace: { _ in .max })
        queue.enqueue(metadata, folders: [.device: device, .drive: drive], holding: nil)
        await queue.wait()

        #expect(queue.outcomes[.drive] == .repairFailed)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: metadata.standIns![0].folderName).appending(path: stem).path))
    }

    /// A Drive only Take whose Device Stop gave up on: the stand-in may still be written there, and the Device may be the
    /// volume that hangs, so nothing on it is removed (and nothing waits on it on the main thread).
    func abandonedDeviceTake(gaps: [TakeMetadata.Gap]) throws -> (metadata: TakeMetadata, device: URL, drive: URL, standIn: URL) {
        let stem = "01 USB 01.wav"
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        func write(_ frames: Int, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let writer = try StemWriter.open(url: url, info: info, resumingAt: nil)
            try [Float](repeating: 0.1, count: frames).withUnsafeBufferPointer { try writer.append($0) }
            try writer.finalize()
        }
        let device = root.appending(path: "Device/Take 01")
        let drive = root.appending(path: "Drive/Take 01")
        try write(10_000, to: drive.appending(path: stem))
        var metadata = metadata(take: 1, gaps: gaps)
        metadata.standIns = [.init(start: 3_000, end: 7_000)]
        let standIn = device.appending(path: metadata.standIns![0].folderName)
        try write(4_000, to: standIn.appending(path: stem))
        try metadata.write(to: device)
        try metadata.write(to: drive)
        return (metadata, device, drive, standIn)
    }

    /// The folders the queue was asked to write the Take.json of off the main thread.
    final class Written: @unchecked Sendable {
        private let lock = NSLock()
        private var _folders: [URL] = []
        func add(_ folder: URL) { lock.withLock { _folders.append(folder) } }
        var folders: [URL] { lock.withLock { _folders } }
    }

    @Test("Drive only: a spare stand-in on a Device Stop gave up on is not removed, stays named, and reads as kept")
    func abandonedDeviceKeepsSpareStandIn() async throws {
        let take = try abandonedDeviceTake(gaps: [])
        let written = Written()
        let queue = TakeRepair(freeSpace: { _ in .max }, writeAbandoned: { _, folder in written.add(folder) })

        queue.enqueue(take.metadata, folders: [.device: take.device, .drive: take.drive], holding: nil, abandoned: [.device])
        await queue.wait()

        #expect(FileManager.default.fileExists(atPath: take.standIn.path), "the Device's stand-in is still there")
        #expect(try TakeMetadata.read(fromTakeFolder: take.drive).standIns != nil, "and still named")
        #expect(queue.standInKept, "the summary says the audio is on the Device until the Drive is back")
        #expect(written.folders == [take.device], "the Device's Take.json is written off the main thread")
    }

    @Test("Drive only: with both Copies Stop gave up on, nothing is removed and both Take.json files are written off the main thread")
    func bothAbandoned() async throws {
        let take = try abandonedDeviceTake(gaps: [.init(copy: .drive, start: 3_000, end: 7_000)])
        let written = Written()
        let queue = TakeRepair(freeSpace: { _ in .max }, writeAbandoned: { _, folder in written.add(folder) })

        queue.enqueue(take.metadata, folders: [.device: take.device, .drive: take.drive], holding: nil, abandoned: [.device, .drive])
        await queue.wait()

        #expect(FileManager.default.fileExists(atPath: take.standIn.path))
        #expect(Set(written.folders) == [take.device, take.drive])
    }

    @Test("Drive only: Repair from a Device Stop gave up on doesn't remove the Device's Take once the Drive has it all")
    func abandonedDeviceIsNotRemovedAfterTheMove() async throws {
        let take = try abandonedDeviceTake(gaps: [.init(copy: .drive, start: 3_000, end: 7_000)])
        let queue = TakeRepair(freeSpace: { _ in .max }, writeAbandoned: { _, _ in })

        queue.enqueue(take.metadata, folders: [.device: take.device, .drive: take.drive], holding: nil, abandoned: [.device])
        await queue.wait()

        #expect(FileManager.default.fileExists(atPath: take.standIn.path), "the Device's stand-in is still there")
        #expect(queue.moved == false)
        #expect(queue.standInKept)
        #expect(try TakeMetadata.read(fromTakeFolder: take.drive).standIns != nil, "and still named")
    }

    @Test("Drive only: overlapping stand-ins with a hole between them don't count as covering the Gap")
    func overlappingStandInsWithAHole() async throws {
        let stem = "01 USB 01.wav"
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        func write(_ frames: Int, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let writer = try StemWriter.open(url: url, info: info, resumingAt: nil)
            try [Float](repeating: 0.1, count: frames).withUnsafeBufferPointer { try writer.append($0) }
            try writer.finalize()
        }
        let device = root.appending(path: "Device/Take 01")
        let drive = root.appending(path: "Drive/Take 01")
        try write(10_000, to: drive.appending(path: stem))
        // Gap 3,000 to 7,000. Stand-ins cover 3,000 to 5,000 twice (overlapping) and nothing of 5,000 to 7,000:
        // their lengths add up to the Gap's, but half of it is missing.
        var metadata = metadata(take: 1, gaps: [.init(copy: .drive, start: 3_000, end: 7_000)])
        metadata.standIns = [.init(start: 3_000, end: 5_000), .init(start: 3_000, end: 5_000)]
        for standIn in metadata.standIns! { try write(2_000, to: device.appending(path: standIn.folderName).appending(path: stem)) }
        try metadata.write(to: device)

        let queue = TakeRepair(freeSpace: { _ in .max })
        queue.enqueue(metadata, folders: [.device: device, .drive: drive], holding: nil)
        await queue.wait()

        #expect(queue.outcomes[.drive] == .repairFailed)
        #expect(FileManager.default.fileExists(atPath: device.path))
    }

    @Test("Where the Device has a Gap of its own inside the Drive's, Repair leaves the Drive's frames there as they are, and fails")
    func sourceGapInsideTargetGap() throws {
        let folders = try folders("a")
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        func write(_ copy: DestinationKind, silent: Range<Int>) throws {
            let stem = try StemWriter.open(url: folders[copy]!.appending(path: "01 USB 01.wav"), info: info, resumingAt: nil)
            try (0..<4_800).map { silent.contains($0) ? 0 : counting()($0, 0) }.withUnsafeBufferPointer { try stem.append($0) }
            try stem.finalize()
        }
        // The Drive has real frames from 2 000 inside its Gap (it resumed there); the Device lost 2 000..<2 100.
        try write(.device, silent: 2_000..<2_100)
        try write(.drive, silent: 1_000..<2_000)
        let metadata = metadata(take: 1, gaps: [.init(copy: .drive, start: 1_000, end: 2_500), .init(copy: .device, start: 2_000, end: 2_100)])

        let repairs = TakeRepair.fill(copies: [.init(kind: .device, folder: folders[.device]!), .init(kind: .drive, folder: folders[.drive]!)], metadata: metadata, skip: [.device])

        let drive = try StemWriter.readSamples(url: folders[.drive]!.appending(path: "01 USB 01.wav"), frames: 0..<4_800)
        #expect(Array(drive[2_000..<2_100]) == (2_000..<2_100).map { counting()($0, 0) }, "the Drive's own frames stay")
        #expect(Array(drive[1_000..<2_000]) == (1_000..<2_000).map { counting()($0, 0) }, "the rest of the Gap is filled")
        #expect(repairs == [.init(copy: .drive, start: 1_000, end: 2_500, outcome: .failed)])
    }
}

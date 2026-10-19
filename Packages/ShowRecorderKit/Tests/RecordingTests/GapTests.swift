import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Testing

/// A Stem that fails every append after `healthyFrames`, standing in for a Destination that went away.
final class FailingStem: StemSink, @unchecked Sendable {
    struct Failure: Error {}
    private let real: StemWriter
    private let healthyFrames: Int
    private var frames = 0
    var frameCount: UInt64 { real.frameCount }

    init(_ real: StemWriter, healthyFrames: Int) {
        self.real = real
        self.healthyFrames = healthyFrames
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws {
        if frames + samples.count > healthyFrames { throw Failure() }
        frames += samples.count
        try real.append(samples)
    }
    func commitHeader() throws { try real.commitHeader() }
    func finalize() throws { try real.finalize() }
    @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try real.setMarkers(markers) }
}

/// A Stem that takes every append but fails its header commit once it holds more than `afterFrames`: a Destination that
/// went away between a write and the commit after it, so the last commit stays where it was.
final class CommitFailingStem: StemSink, @unchecked Sendable {
    struct Failure: Error {}
    private let real: StemWriter
    private let afterFrames: Int
    var frameCount: UInt64 { real.frameCount }

    init(_ real: StemWriter, afterFrames: Int) {
        self.real = real
        self.afterFrames = afterFrames
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws { try real.append(samples) }
    func commitHeader() throws {
        if real.frameCount > UInt64(afterFrames) { throw Failure() }
        try real.commitHeader()
    }
    func finalize() throws { try real.finalize() }
    @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try real.setMarkers(markers) }
}

@MainActor
@Suite("Gaps")
struct GapTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "GapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }


    /// A recorder whose Copy on each named Destination fails after `healthyFrames`.
    func recorder(failing failing: Set<DestinationKind>, healthyFrames: Int = 480) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                let kind: DestinationKind = url.path.contains("/Drive/") ? .drive : .device
                return failing.contains(kind) && resuming == nil ? FailingStem(real, healthyFrames: healthyFrames) : real
            }, destinationCheckInterval: nil)
    }

    @Test("A Device that fails mid-Take is marked interrupted and the Drive Copy carries on")
    func deviceFailsMidTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.device])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.device] == .interrupted }

        #expect(recorder.copies[.device] == .interrupted)
        #expect(recorder.copies[.drive] == .recording)
        try await recorder.stopTake()

        let driveStem = try ParsedStem(contentsOf: drive.appending(path: "2026-10-06 Show/Take 01/01 USB 01.wav"))
        #expect(driveStem.samples.count == 4800)
    }

    @Test("When every Copy has failed the Take ends on its own")
    func takeEndsWhenEveryCopyFailed() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.device, .drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(3, to: audio, recorder, sample: counting())
        try await waitUntil { !recorder.isRecording && !recorder.isFinishing }

        #expect(!recorder.isRecording)
        #expect(recorder.lastTakeEnd == TakeEnd(take: 1, reason: .noDestination))
        #expect(Set(try decodedTake(device).gaps.map(\.copy)) == [.device, .drive])
    }

    @Test("A Drive that fails mid-Take is marked interrupted and the Device Copy carries on")
    func driveFailsMidTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                return url.path.hasPrefix(drive.resolvingSymlinksInPath().path) || url.path.hasPrefix(drive.path)
                    ? FailingStem(real, healthyFrames: 480) : real
            }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.drive] == .interrupted }

        #expect(recorder.copies[.device] == .recording)
        #expect(recorder.copies[.drive] == .interrupted)
        try await recorder.stopTake()

        let deviceStem = try ParsedStem(contentsOf: device.appending(path: "2026-10-06 Show/Take 01/01 USB 01.wav"))
        #expect(deviceStem.samples.count == 4800)

        // The Drive Copy is missing everything after its last commit (the one at the start, #595); the Device's
        // Take.json says so.
        let json = try Data(contentsOf: device.appending(path: "2026-10-06 Show/Take 01/Take.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(TakeMetadata.self, from: json).gaps == [.init(copy: .drive, start: 0, end: 4800)])
    }

    @Test("With no Drive at record the Take starts on the Device and the Drive Copy is missing")
    func noDriveAtStartIsMissing() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()

        #expect(recorder.isRecording)
        #expect(recorder.copies[.device] == .recording)
        #expect(recorder.copies[.drive] == .missing)
        try await recorder.stopTake()
        #expect(recorder.copies[.drive] == .missing)
    }

    @Test("A Drive that appears mid-Take joins with the missed span written as silence and recorded as a Gap")
    func driveJoinsMidTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let available = DriveSwitch()
        let recorder = Recorder(deviceFolder: device, driveFolder: { available.folder.map { DriveAccess(folder: $0) } }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        available.folder = drive
        await recorder.checkDestinations()
        #expect(recorder.copies[.drive] == .recording)
        try await deliverBlocks(5, from: 4_800, to: audio, recorder, sample: counting())
        try await recorder.stopTake()

        let take = "2026-10-06 Show/Take 01"
        let deviceStem = try ParsedStem(contentsOf: device.appending(path: "\(take)/01 USB 01.wav"))
        let driveStem = try ParsedStem(contentsOf: drive.appending(path: "\(take)/01 USB 01.wav"))
        #expect(deviceStem.samples.count == 7200)
        #expect(driveStem.samples.count == 7200)
        #expect(driveStem.samples[..<4800].allSatisfy { $0 == 0 })
        #expect(Array(driveStem.samples[4800...]) == Array(deviceStem.samples[4800...]))

        let report = try String(contentsOf: device.appending(path: "2026-10-06 Show/Report.html"), encoding: .utf8)
        #expect(report.contains("<h3>Gaps</h3>"))
        #expect(report.contains("<td>Drive</td><td class=\"num\">0:00.0</td><td class=\"num\">0:00.1</td>"))

        let expected = [TakeMetadata.Gap(copy: .drive, start: 0, end: 4800)]
        for folder in [device, drive] {
            let json = try Data(contentsOf: folder.appending(path: "\(take)/Take.json"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            #expect(try decoder.decode(TakeMetadata.self, from: json).gaps == expected)
        }
    }

    @Test("A Drive that comes back after failing reopens the same Stems, with silence for the Gap")
    func driveComesBackAfterFailing() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.drive])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        await recorder.checkDestinations()
        #expect(recorder.copies[.drive] == .recording)
        try await deliverBlocks(5, from: 4_800, to: audio, recorder, sample: counting())
        try await recorder.stopTake()

        let take = "2026-10-06 Show/Take 01"
        let deviceStem = try ParsedStem(contentsOf: device.appending(path: "\(take)/01 USB 01.wav"))
        let driveStem = try ParsedStem(contentsOf: drive.appending(path: "\(take)/01 USB 01.wav"))
        #expect(driveStem.samples.count == 7200)
        // It resumes at its last commit, the one at the start (#595).
        #expect(driveStem.samples[..<4800].allSatisfy { $0 == 0 })
        #expect(Array(driveStem.samples[4800...]) == Array(deviceStem.samples[4800...]))
        for folder in [device, drive] {
            let json = try Data(contentsOf: folder.appending(path: "\(take)/Take.json"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            #expect(try decoder.decode(TakeMetadata.self, from: json).gaps == [.init(copy: .drive, start: 0, end: 4800)])
        }
    }

    func decodedTake(_ folder: URL) throws -> TakeMetadata {
        let json = try Data(contentsOf: folder.appending(path: "2026-10-06 Show/Take 01/Take.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: json)
    }

    @Test("Markers keep their place on the Take timeline after the Device Copy stops")
    func markersAfterDeviceFails() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = recorder(failing: [.device])
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.device] == .interrupted }
        try await deliverBlocks(5, to: audio, recorder, sample: counting())
        recorder.addMarker(named: "Encore")
        try await recorder.stopTake()

        #expect(try decodedTake(drive).markers.map(\.position) == [7200])
        let cues = try cuePoints(drive.appending(path: "2026-10-06 Show/Take 01/01 USB 01.wav"))
        #expect(cues == [CuePoint(position: 7200, label: "Encore")])
    }

    @Test("Audio arriving while no Take is running doesn't move the Take timeline")
    func idleAudioDoesNotCountTowardTheTake() {
        let capture = Capture(channelCount: 1, sampleRate: 48_000)
        let samples: [Float] = Array(repeating: 0, count: 480)
        samples.withUnsafeBufferPointer { buffer in
            var channel = buffer.baseAddress!
            withUnsafePointer(to: &channel) { channels in
                capture.receive(AudioBlock(channels: channels, channelCount: 1, frameCount: 480, hostTime: 0))
            }
        }
        #expect(capture.takeFrameCount == 0)
    }

    @Test("A Drive that joins mid-Take gets the Markers placed before it joined")
    func joiningDriveGetsEarlierMarkers() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let available = DriveSwitch()
        let recorder = Recorder(deviceFolder: device, driveFolder: { available.folder.map { DriveAccess(folder: $0) } }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        recorder.addMarker(named: "Verse")
        available.folder = drive
        await recorder.checkDestinations()
        try await deliverBlocks(5, to: audio, recorder, sample: counting())
        try await recorder.stopTake()

        let take = "2026-10-06 Show/Take 01/01 USB 01.wav"
        let expected = [CuePoint(position: 4800, label: "Verse")]
        #expect(try cuePoints(device.appending(path: take)) == expected)
        #expect(try cuePoints(drive.appending(path: take)) == expected)
    }

    @Test("A Drive that comes back at a new path is written there, not at the old one")
    func driveComesBackAtNewPath() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let available = DriveSwitch()
        available.folder = drive
        let remounted = root.appending(path: "Drive 2")
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { available.folder.map { DriveAccess(folder: $0) } },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                return resuming == nil && url.path.contains("/Drive/") ? FailingStem(real, healthyFrames: 480) : real
            }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        try FileManager.default.moveItem(at: drive, to: remounted)
        available.folder = remounted
        await recorder.checkDestinations()
        try await deliverBlocks(5, to: audio, recorder, sample: counting())
        try await recorder.stopTake()

        let moved = try ParsedStem(contentsOf: remounted.appending(path: "2026-10-06 Show/Take 01/01 USB 01.wav"))
        #expect(moved.samples.count == 7200)
        #expect(!FileManager.default.fileExists(atPath: drive.path))
    }

    @Test("A Copy short of space stops cleanly while another has room; the Take finalizes before the last one fills")
    func diskFullFinalizesBeforeLastCopyFills() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let free = FreeSpace(device: 100_000_000, drive: 100_000_000)
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            freeSpace: { free.bytes(at: $0) }, destinationCheckInterval: nil)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliverBlocks(4, to: audio, recorder, sample: counting())
        // 60 s of one 48 kHz 24-bit channel is 8.64 MB.
        free.device = 5_000_000
        await recorder.checkDestinations()
        #expect(recorder.isRecording)
        #expect(recorder.copies[.device] == .full, "retired for space, not failed (#560)")
        #expect(recorder.copies[.drive] == .recording)

        try await deliverBlocks(2, to: audio, recorder, sample: counting())
        free.drive = 5_000_000
        await recorder.checkDestinations()

        #expect(!recorder.isRecording)
        let take = "2026-10-06 Show/Take 01"
        #expect(try ParsedStem(contentsOf: device.appending(path: "\(take)/01 USB 01.wav")).samples.count == 4 * 480)
        #expect(try ParsedStem(contentsOf: drive.appending(path: "\(take)/01 USB 01.wav")).samples.count == 6 * 480)
    }
}

/// Free space per Destination, set by a test and read from the thread that checks Destinations (#814).
final class FreeSpace: @unchecked Sendable {
    private let lock = NSLock()
    private var deviceBytes: Int64
    private var driveBytes: Int64
    var device: Int64 {
        get { lock.withLock { deviceBytes } }
        set { lock.withLock { deviceBytes = newValue } }
    }
    var drive: Int64 {
        get { lock.withLock { driveBytes } }
        set { lock.withLock { driveBytes = newValue } }
    }

    init(device: Int64, drive: Int64) {
        deviceBytes = device
        driveBytes = drive
    }

    func bytes(at url: URL) -> Int64 {
        url.path.contains("/Drive/") ? drive : device
    }
}

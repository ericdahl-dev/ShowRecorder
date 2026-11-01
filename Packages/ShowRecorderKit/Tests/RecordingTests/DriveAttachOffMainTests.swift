import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Testing

/// A Drive that joins or rejoins a running Take creates its Stems on a slow stick, 18 files at 0.7 s each on the stick
/// that stuttered (#814). That is file work, so it runs off the main actor; only the writer's wiring runs on it.
@MainActor
@Suite("Drive attach off the main actor")
struct DriveAttachOffMainTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let capture = Capture(channelCount: 1, sampleRate: 48_000)

    /// Notes the threads Stems were made on, and holds the Drive's Stem creation on a gate when asked.
    final class Creation: @unchecked Sendable {
        private let lock = NSLock()
        private var onMain = 0
        private var offMain = 0
        private var began = false
        let gate = TestGate()
        /// Creating the Drive's Stems waits on the gate (from the first Stem on) when true.
        var holds = false
        func made(onDrive: Bool) {
            lock.withLock {
                if onDrive { if Thread.isMainThread { onMain += 1 } else { offMain += 1 } }
            }
        }
        func enteredDrive() { lock.withLock { began = true } }
        /// Forgets that creation began, for a test that makes the Drive's Stems more than once.
        func resetBegun() { lock.withLock { began = false } }
        var driveStemsOnMain: Int { lock.withLock { onMain } }
        var driveStemsOffMain: Int { lock.withLock { offMain } }
        var hasBegun: Bool { lock.withLock { began } }
    }

    /// Counts how often a DriveAccess was let go.
    final class Released: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "DriveAttachOffMainTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Device"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// A Take on the Device only, as one started with no Drive.
    func session(_ creation: Creation, driveStem: @escaping @Sendable (StemWriter) -> any StemSink = { $0 }) throws -> TakeSession {
        var show = try Show.create(in: device, drive: nil, on: RecordingTakeTests.showDay)
        let folders = try show.createNextTakeFolder()
        let metadata = TakeMetadata(
            show: show.name, take: show.takeCount, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "ShowRecorder", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        let drive = drive
        return try TakeSession(
            show: show, folders: folders, drive: nil, metadata: metadata,
            stems: [StemSpec(file: "01 USB 01.wav", description: "USB 01")], info: info, capture: capture,
            makeStem: { url, info, resuming in
                let onDrive = url.path.hasPrefix(drive.path)
                creation.made(onDrive: onDrive)
                if onDrive {
                    creation.enteredDrive()
                    if creation.holds { creation.gate.wait() }
                }
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                return onDrive && resuming == nil ? driveStem(real) : real
            },
            freeSpace: { _ in .max })
    }

    /// Yields the main actor until Stem creation on the Drive has begun. The minute only guards against a hang.
    func awaitBegun(_ creation: Creation) async {
        let deadline = ContinuousClock.now + .seconds(60)
        while !creation.hasBegun, ContinuousClock.now < deadline { await Task.yield() }
    }

    func deliver(_ frames: Int) async throws {
        var samples = [Float](repeating: 0.25, count: frames)
        samples.withUnsafeMutableBufferPointer { buffer in
            var pointer = UnsafePointer(buffer.baseAddress!)
            withUnsafePointer(to: &pointer) {
                capture.receive(AudioBlock(channels: $0, channelCount: 1, frameCount: frames, hostTime: 0))
            }
        }
        try await waitUntil { capture.isDrained }
    }

    @Test("A Drive that joins mid-Take has its Stems made off the main thread, then joins")
    func joinMakesStemsOffMain() async throws {
        let creation = Creation()
        let session = try session(creation)
        try await deliver(480)
        let drive = drive

        let attached = await session.attachDriveOffMain(drive: { DriveAccess(folder: drive) })

        #expect(attached)
        #expect(session.copies.map(\.kind) == [.device, .drive])
        #expect(creation.driveStemsOffMain == 1)
        #expect(creation.driveStemsOnMain == 0)
        try await deliver(480)
        let finished = session.finish()
        #expect(finished.metadata.gaps == [.init(copy: .drive, start: 0, end: 480)])
    }

    @Test("While the Drive's Stems are being made the main actor stays free, and Stop-side cancel finds an attach under way")
    func mainStaysFree() async throws {
        let creation = Creation()
        creation.holds = true
        defer { creation.gate.open() }
        let session = try session(creation)
        try await deliver(480)
        let drive = drive

        let attaching = Task { @MainActor in await session.attachDriveOffMain(drive: { DriveAccess(folder: drive) }) }
        await awaitBegun(creation)

        #expect(creation.hasBegun, "creation began")
        #expect(creation.driveStemsOnMain == 0, "and not on the main thread")
        #expect(session.isAttaching)
        creation.gate.open()
        #expect(await attaching.value)
        #expect(!session.isAttaching)
        _ = session.finish()
    }

    @Test("A first join canceled while its Stems are being made leaves nothing on the Drive and lets the access go")
    func canceledFirstJoin() async throws {
        let creation = Creation()
        creation.holds = true
        defer { creation.gate.open() }
        let session = try session(creation)
        try await deliver(480)
        let drive = drive
        let released = Released()

        let attaching = Task { @MainActor in
            await session.attachDriveOffMain(drive: { DriveAccess(folder: drive, stop: { released.increment() }) })
        }
        await awaitBegun(creation)
        session.cancelAttach()
        creation.gate.open()

        #expect(await attaching.value == false)
        #expect(session.copies.map(\.kind) == [.device], "no Drive Copy")
        let takeOnDrive = drive.appending(path: "\(session.show.name)/Take 01")
        #expect(!FileManager.default.fileExists(atPath: takeOnDrive.path), "the Take folder it made is gone")
        #expect(released.count == 1)
        #expect(ShowFile.read(from: session.show.folder)?.driveCopyWritten != true, "Show.json doesn't claim a Drive copy")
        _ = session.finish()
    }

    @Test("A rejoin canceled while its Stems are being made keeps the failed Copy's files and the failed Copy")
    func canceledRejoin() async throws {
        let creation = Creation()
        let session = try session(creation, driveStem: { FailingStem($0, healthyFrames: 480) })
        try await deliver(480)
        let drive = drive
        #expect(await session.attachDriveOffMain(drive: { DriveAccess(folder: drive) }))
        for _ in 0..<3 { try await deliver(480) }
        try await waitUntil { session.copies[1].writer.isFinished && session.copies[1].writer.hasFailed }
        let stemOnDrive = session.copies[1].folder.appending(path: "01 USB 01.wav")
        let released = Released()
        creation.holds = true
        creation.resetBegun()
        defer { creation.gate.open() }

        let rejoining = Task { @MainActor in
            await session.attachDriveOffMain(drive: { DriveAccess(folder: drive, stop: { released.increment() }) })
        }
        await awaitBegun(creation)
        session.cancelAttach()
        creation.gate.open()

        #expect(await rejoining.value == false)
        #expect(session.copies.count == 2, "the failed Drive Copy is still the Take's")
        #expect(FileManager.default.fileExists(atPath: stemOnDrive.path), "its files are kept")
        #expect(released.count == 1)
        _ = session.finish()
    }

    @Test("A Marker placed while the Drive's Stems are being made is in the new Copy's Take.json")
    func markerDuringTheAttach() async throws {
        let creation = Creation()
        creation.holds = true
        defer { creation.gate.open() }
        let session = try session(creation)
        try await deliver(480)
        let drive = drive

        let attaching = Task { @MainActor in await session.attachDriveOffMain(drive: { DriveAccess(folder: drive) }) }
        await awaitBegun(creation)
        let marker = session.addMarker()
        creation.gate.open()
        #expect(await attaching.value)

        let onDrive = try TakeMetadata.read(fromTakeFolder: session.copies[1].folder)
        #expect(onDrive.markers.contains(marker), "the Drive's Take.json knows the Marker")
        _ = session.finish()
    }

    @Test("A canceled attach is over: a later one can start")
    func attachAfterCancel() async throws {
        let creation = Creation()
        let session = try session(creation)
        try await deliver(480)
        let drive = drive
        session.cancelAttach()   // nothing under way: the next attach is not born canceled

        let attached = await session.attachDriveOffMain(drive: { DriveAccess(folder: drive) })

        #expect(attached)
        _ = session.finish()
    }

    @Test("The periodic check starts a Drive join and returns, so the next checks keep running while the Stems are made")
    func periodicCheckDoesNotWait() async throws {
        let creation = Creation()
        creation.holds = true
        defer { creation.gate.open() }
        let drive = drive
        let available = DriveSwitch()
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { available.folder.map { DriveAccess(folder: $0) } }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                if url.path.hasPrefix(drive.path) {
                    creation.enteredDrive()
                    creation.gate.wait()
                }
                return try StemWriter.open(url: url, info: info, resumingAt: resuming)
            }, destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.25, count: 480)])
        available.folder = drive

        // What the one-second loop calls. It must come back with the Stems still held on the gate; had it waited for
        // them, this line would sit until the gate's guard ended the wait.
        await recorder.checkDestinations(awaitingDrive: false)

        await awaitBegun(creation)
        #expect(creation.hasBegun, "the join is under way")
        await recorder.checkDestinations(awaitingDrive: false)   // the next tick comes straight back, with the join still going
        creation.gate.open()
        try await recorder.stopTake()
    }

    @Test("Stop while the Drive's Stems are being made ends the Take without that Drive, and leaves nothing half-made on it")
    func stopDuringTheAttach() async throws {
        let creation = Creation()
        creation.holds = true
        defer { creation.gate.open() }
        let drive = drive
        let released = Released()
        let available = DriveSwitch()
        let recorder = Recorder(
            deviceFolder: device,
            driveFolder: { available.folder.map { DriveAccess(folder: $0, stop: { released.increment() }) } },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                if url.path.hasPrefix(drive.path) {
                    creation.enteredDrive()
                    creation.gate.wait()
                }
                return try StemWriter.open(url: url, info: info, resumingAt: resuming)
            },
            destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()  // the Drive isn't there at the press
        audio.deliver([Array(repeating: 0.25, count: 480)])
        available.folder = drive

        let checking = Task { @MainActor in await recorder.checkDestinations() }
        await awaitBegun(creation)
        #expect(creation.hasBegun, "the Drive's Stems were being made")
        try await recorder.stopTake()
        creation.gate.open()
        await checking.value

        #expect(!recorder.isRecording)
        #expect(recorder.copies[.drive] == .missing, "the Take has no Drive Copy")
        let showOnDrive = try FileManager.default.contentsOfDirectory(atPath: drive.path).first.map { drive.appending(path: $0) }
        let takes = showOnDrive.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path).filter { $0.hasPrefix("Take ") } } ?? []
        #expect(takes.isEmpty, "no Take folder left half-made on the Drive")
        #expect(released.count == 1, "the access was let go")
    }

    @Test("A Take already Ready on a Drive has nothing to attach")
    func nothingToAttach() async throws {
        let creation = Creation()
        let session = try session(creation)
        try await deliver(480)
        let drive = drive
        #expect(await session.attachDriveOffMain(drive: { DriveAccess(folder: drive) }))

        let again = await session.attachDriveOffMain(drive: { DriveAccess(folder: drive) })

        #expect(!again, "the Drive Copy is healthy")
        #expect(session.copies.count == 2)
        _ = session.finish()
    }
}

import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Synchronization
import TakeFile
import Testing

/// The Drive's file work at a Take's start (the Show and Take folders on it, the Stems and `Take.json`) is done before the
/// session exists, on a thread of its own, so pressing Take never waits on a slow stick on the main thread (#914).
@MainActor
@Suite("A Drive prepared before the Take starts")
struct DriveStartPreparedTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let capture = Capture(channelCount: 1, sampleRate: 48_000)
    let stems = [StemSpec(file: "01 USB 01.wav", description: "USB 01")]
    let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "ShowRecorder", timeReference: 0, originationDate: RecordingTakeTests.showDay)

    /// Counts the Stems made on the Drive.
    final class Made: @unchecked Sendable {
        private let lock = NSLock()
        private var drive = 0
        func onDrive() { lock.withLock { drive += 1 } }
        var driveStems: Int { lock.withLock { drive } }
    }

    /// Counts how often something happened.
    final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() { lock.withLock { value += 1 } }
        var n: Int { lock.withLock { value } }
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "DriveStartPreparedTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Device"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// A Show on the Device with its Take folder made there, as at the press.
    func deviceTake() throws -> (show: Show, folders: [DestinationKind: URL], metadata: TakeMetadata) {
        var show = try Show.create(in: device, drive: nil, on: RecordingTakeTests.showDay)
        let folders = try show.createNextTakeFolder()
        let metadata = TakeMetadata(
            show: show.name, take: show.takeCount, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        return (show, folders, metadata)
    }

    func makeStem(_ made: Made) -> @Sendable (URL, StemWriter.Info, UInt64?) throws -> any StemSink {
        let drive = drive
        return { url, info, resuming in
            if url.path.hasPrefix(drive.path) { made.onDrive() }
            return try StemWriter.open(url: url, info: info, resumingAt: resuming)
        }
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

    @Test("A session given a prepared Drive makes no Drive Stems itself and records to the prepared ones")
    func sessionUsesThePreparedDrive() async throws {
        let (show, deviceFolders, metadata) = try deviceTake()
        let made = Made()
        let make = makeStem(made)
        let drive = drive
        let prepared = try #require(await runOffPool {
            TakeSession.prepareDriveStart(
                show: show, metadata: metadata, stems: stems, info: info, makeStem: make, freeSpace: { _ in .max },
                drive: { DriveAccess(folder: drive) }, cancel: AttachCancel())
        })
        #expect(made.driveStems == 1, "the job made the Drive's Stem")

        let session = try TakeSession(
            show: prepared.show, folders: deviceFolders.merging([.drive: prepared.folder]) { $1 }, drive: prepared.access,
            metadata: metadata, stems: stems, info: info, capture: capture, makeStem: make, freeSpace: { _ in .max },
            preparedDrive: prepared)

        #expect(made.driveStems == 1, "the session made none")
        #expect(session.copies.map(\.kind) == [.device, .drive])
        #expect(FileManager.default.fileExists(atPath: deviceFolders[.device]!.appending(path: "Take.json").path), "the Device's Take.json")
        #expect(FileManager.default.fileExists(atPath: prepared.folder.appending(path: "Take.json").path), "the Drive's, from the job")
        try await deliver(480)
        _ = session.finish()
        #expect(try StemWriter.readSamples(url: prepared.folder.appending(path: "01 USB 01.wav"), frames: 0..<480) == [Float](repeating: 0.25, count: 480))
    }

    /// Three channels, so a job has Stems to be stopped between.
    var threeStems: [StemSpec] { (1...3).map { StemSpec(file: "0\($0) USB 0\($0).wav", description: "USB 0\($0)") } }

    func threeChannelMetadata(_ show: Show) -> TakeMetadata {
        TakeMetadata(
            show: show.name, take: show.takeCount, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: (1...3).map { .init(usbChannel: $0, stemFile: "0\($0) USB 0\($0).wav", source: .fallback(usbChannel: $0)) })
    }

    /// An earlier Take already on the Drive, in the Show's folder there.
    func earlierTakeOnDrive(of show: Show) throws -> URL {
        let earlier = drive.appending(path: "\(show.name)/Take 00", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: earlier, withIntermediateDirectories: true)
        try Data("earlier".utf8).write(to: earlier.appending(path: "01 USB 01.wav"))
        return earlier
    }

    @Test("A job canceled before it starts asks for no Drive and makes nothing")
    func canceledBeforeItStarts() throws {
        let (show, _, metadata) = try deviceTake()
        let cancel = AttachCancel()
        cancel.cancel()
        let asked = Made()
        let drive = drive

        let prepared = TakeSession.prepareDriveStart(
            show: show, metadata: metadata, stems: stems, info: info, makeStem: makeStem(asked), freeSpace: { _ in .max },
            drive: { asked.onDrive(); return DriveAccess(folder: drive) }, cancel: cancel)

        #expect(prepared == nil)
        #expect(asked.driveStems == 0, "neither the Drive nor a Stem was reached for")
        #expect(try FileManager.default.contentsOfDirectory(atPath: drive.path).isEmpty)
    }

    @Test("A Drive that isn't there gives no job")
    func noDrive() throws {
        let (show, _, metadata) = try deviceTake()
        let prepared = TakeSession.prepareDriveStart(
            show: show, metadata: metadata, stems: stems, info: info, makeStem: makeStem(Made()), freeSpace: { _ in .max },
            drive: { nil }, cancel: AttachCancel())
        #expect(prepared == nil)
    }

    @Test("A job canceled between Stems removes only the Take folder it made: the Show folder and an earlier Take stay (#914)")
    func canceledBetweenStems() throws {
        let (show, _, _) = try deviceTake()
        let metadata = threeChannelMetadata(show)
        let earlier = try earlierTakeOnDrive(of: show)
        let cancel = AttachCancel()
        let made = Made()
        let released = Count()
        let drive = drive
        let counting = makeStem(made)

        let prepared = TakeSession.prepareDriveStart(
            show: show, metadata: metadata, stems: threeStems, info: info,
            makeStem: { url, info, resuming in
                let sink = try counting(url, info, resuming)
                if made.driveStems == 2 { cancel.cancel() }
                return sink
            }, freeSpace: { _ in .max },
            drive: { DriveAccess(folder: drive, stop: { released.bump() }) }, cancel: cancel)

        #expect(prepared == nil)
        #expect(made.driveStems == 2, "no Stem after the cancel")
        let showOnDrive = drive.appending(path: show.name)
        #expect(FileManager.default.fileExists(atPath: showOnDrive.path), "the Show folder stays")
        #expect(FileManager.default.fileExists(atPath: earlier.appending(path: "01 USB 01.wav").path), "the earlier Take stays")
        #expect(!FileManager.default.fileExists(atPath: showOnDrive.appending(path: "Take 01").path), "the Take folder it made is gone")
        #expect(released.n == 1, "the access was let go")
    }

    @Test("A job canceled while a Stem is being made stops there: when it returns, nothing of it is left (#914)")
    func lateFinishAfterCancel() async throws {
        let (show, _, _) = try deviceTake()
        let metadata = threeChannelMetadata(show)
        let earlier = try earlierTakeOnDrive(of: show)
        let cancel = AttachCancel()
        let gate = TestGate()
        let made = Made()
        let entered = Made()
        let counting = makeStem(made)
        let drive = drive
        let threeStems = threeStems
        let info = info

        let job = Task {
            await runOffPool {
                TakeSession.prepareDriveStart(
                    show: show, metadata: metadata, stems: threeStems, info: info,
                    makeStem: { url, info, resuming in
                        if made.driveStems == 1 { entered.onDrive(); gate.wait() }
                        return try counting(url, info, resuming)
                    }, freeSpace: { _ in .max }, drive: { DriveAccess(folder: drive) }, cancel: cancel)
            }
        }
        let deadline = ContinuousClock.now + .seconds(60)
        while entered.driveStems == 0, ContinuousClock.now < deadline { await Task.yield() }
        #expect(entered.driveStems == 1, "the job is inside the second Stem")

        // The caller gives up while the stick is still answering the second Stem.
        cancel.cancel()
        gate.open()
        let prepared = await job.value

        #expect(prepared == nil)
        #expect(made.driveStems == 2, "the third Stem was never made")
        let showOnDrive = drive.appending(path: show.name)
        #expect(!FileManager.default.fileExists(atPath: showOnDrive.appending(path: "Take 01").path), "nothing of the job is left")
        #expect(FileManager.default.fileExists(atPath: earlier.appending(path: "01 USB 01.wav").path))
    }

    @Test("A Drive only session given a prepared Drive stands by on the Device: nothing of the Take is written there")
    func driveOnlyStandsBy() async throws {
        let (show, deviceFolders, metadata) = try deviceTake()
        let made = Made()
        let make = makeStem(made)
        let drive = drive
        let preparedOrNil = TakeSession.prepareDriveStart(
                show: show, metadata: metadata, stems: stems, info: info, makeStem: make, freeSpace: { _ in .max },
                drive: { DriveAccess(folder: drive) }, cancel: AttachCancel())
        let prepared = try #require(preparedOrNil)

        let session = try TakeSession(
            show: prepared.show, folders: deviceFolders.merging([.drive: prepared.folder]) { $1 }, drive: prepared.access,
            metadata: metadata, stems: stems, info: info, capture: capture, makeStem: make, freeSpace: { _ in .max },
            driveOnly: true, preparedDrive: prepared)
        try await deliver(480)
        let onDeviceWhileRecording = try FileManager.default.contentsOfDirectory(atPath: deviceFolders[.device]!.path)
        _ = session.finish()

        #expect(onDeviceWhileRecording.isEmpty, "nothing in the Device's Take folder while the Drive records: \(onDeviceWhileRecording)")
        #expect(made.driveStems == 1)
        #expect(try StemWriter.readSamples(url: prepared.folder.appending(path: "01 USB 01.wav"), frames: 0..<480) == [Float](repeating: 0.25, count: 480))
        #expect(!FileManager.default.fileExists(atPath: deviceFolders[.device]!.path), "no Take folder on the Device, as for any healthy Drive only Take")
    }

    /// Asks for a DriveAccess that counts how often it was let go.
    func access(_ released: Count) -> @Sendable () -> DriveAccess? {
        let drive = drive
        return { DriveAccess(folder: drive, stop: { released.bump() }) }
    }

    @Test("A cancel that comes while the Drive is still being asked for ends the job before it writes anything, and lets the access go")
    func canceledWhileTheDriveIsAsked() async throws {
        let (show, _, metadata) = try deviceTake()
        let cancel = AttachCancel()
        let gate = TestGate()
        let asked = Made()
        let released = Count()
        let make = makeStem(Made())
        let stems = stems, info = info
        let access = access(released)

        let job = Task {
            await runOffPool {
                TakeSession.prepareDriveStart(
                    show: show, metadata: metadata, stems: stems, info: info, makeStem: make, freeSpace: { _ in .max },
                    drive: { asked.onDrive(); gate.wait(); return access() }, cancel: cancel)
            }
        }
        let deadline = ContinuousClock.now + .seconds(60)
        while asked.driveStems == 0, ContinuousClock.now < deadline { await Task.yield() }
        cancel.cancel()
        gate.open()

        #expect(await job.value == nil)
        #expect(released.n == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: drive.path).isEmpty, "no Show folder, no Show.json on the Drive")
        #expect(ShowFile.read(from: show.folder)?.driveCopyWritten != true, "and none claimed on the Device")
    }

    @Test("A job never writes the Device's Show.json, so one canceled long after the press can't undo what the main actor wrote since")
    func neverTouchesTheDevicesShowJSON() throws {
        let (show, _, _) = try deviceTake()
        let metadata = threeChannelMetadata(show)
        // The main actor has moved on: the Show.json on the Device is newer than the job's copy of the Show.
        var newer = try #require(ShowFile.read(from: show.folder))
        newer.takes = 7
        newer.lastTakeEndedAt = RecordingTakeTests.showDay
        try newer.write(to: show.folder)
        let cancel = AttachCancel()
        let made = Made()
        let counting = makeStem(made)
        let drive = drive

        let canceled = TakeSession.prepareDriveStart(
            show: show, metadata: metadata, stems: threeStems, info: info,
            makeStem: { url, info, resuming in
                let sink = try counting(url, info, resuming)
                if made.driveStems == 2 { cancel.cancel() }
                return sink
            }, freeSpace: { _ in .max }, drive: { DriveAccess(folder: drive) }, cancel: cancel)
        #expect(canceled == nil)
        #expect(ShowFile.read(from: show.folder) == newer, "after a canceled job")

        let finished = TakeSession.prepareDriveStart(
            show: show, metadata: metadata, stems: threeStems, info: info, makeStem: counting, freeSpace: { _ in .max },
            drive: { DriveAccess(folder: drive) }, cancel: AttachCancel())
        #expect(finished != nil)
        #expect(ShowFile.read(from: show.folder) == newer, "and after one that finished")
    }

    @Test("A job that fails, or finds no room, lets the access go exactly once")
    func failureLetsTheAccessGo() throws {
        struct Boom: Error {}
        let (show, _, metadata) = try deviceTake()
        let released = Count()
        let access = access(released)

        let failed = TakeSession.prepareDriveStart(
            show: show, metadata: metadata, stems: stems, info: info, makeStem: { _, _, _ in throw Boom() }, freeSpace: { _ in .max },
            drive: access, cancel: AttachCancel())
        #expect(failed == nil)
        #expect(released.n == 1, "a Stem that can't be made")

        let noRoom = TakeSession.prepareDriveStart(
            show: show, metadata: metadata, stems: stems, info: info, makeStem: makeStem(Made()), freeSpace: { _ in 0 },
            drive: access, cancel: AttachCancel())
        #expect(noRoom == nil)
        #expect(released.n == 2, "a Drive with no room")
    }

    @Test("A prepared Drive the caller drops (the deadline came as the job finished) is closed, its Take folder removed, the access let go")
    func discardingAPreparedDrive() throws {
        let (show, _, metadata) = try deviceTake()
        let earlier = try earlierTakeOnDrive(of: show)
        let released = Count()
        let access = access(released)
        let preparedOrNil = TakeSession.prepareDriveStart(
                show: show, metadata: metadata, stems: stems, info: info, makeStem: makeStem(Made()), freeSpace: { _ in .max },
                drive: access, cancel: AttachCancel())
        let prepared = try #require(preparedOrNil)
        #expect(FileManager.default.fileExists(atPath: prepared.folder.path))

        TakeSession.discardDriveStart(prepared)

        #expect(!FileManager.default.fileExists(atPath: prepared.folder.path))
        #expect(FileManager.default.fileExists(atPath: earlier.appending(path: "01 USB 01.wav").path), "an earlier Take stays")
        #expect(released.n == 1)
    }

    @Test("The session takes the Drive's folder and access from the prepared Drive and hands that access to Repair at the end")
    func accessComesFromThePreparedDrive() async throws {
        let (show, deviceFolders, metadata) = try deviceTake()
        let released = Count()
        let access = access(released)
        let make = makeStem(Made())
        let preparedOrNil = TakeSession.prepareDriveStart(
                show: show, metadata: metadata, stems: stems, info: info, makeStem: make, freeSpace: { _ in .max },
                drive: access, cancel: AttachCancel())
        let prepared = try #require(preparedOrNil)

        // The Drive's folder and access are left out of the arguments: they come from `preparedDrive`.
        let session = try TakeSession(
            show: prepared.show, folders: deviceFolders, drive: nil, metadata: metadata, stems: stems, info: info, capture: capture,
            makeStem: make, freeSpace: { _ in .max }, preparedDrive: prepared)
        #expect(session.copies.map(\.kind) == [.device, .drive])
        #expect(session.copies.last?.folder == prepared.folder)
        try await deliver(480)
        let finished = session.finish()
        #expect(released.n == 0, "held to the end of the Take, as before")
        finished.access?.end()
        #expect(released.n == 1, "the access Repair gets is the prepared one")
    }

    @Test("A session that can't start on the Device cleans up the prepared Drive it was given")
    func initFailureCleansUp() throws {
        struct Boom: Error {}
        let (show, deviceFolders, metadata) = try deviceTake()
        let released = Count()
        let access = access(released)
        let preparedOrNil = TakeSession.prepareDriveStart(
                show: show, metadata: metadata, stems: stems, info: info, makeStem: makeStem(Made()), freeSpace: { _ in .max },
                drive: access, cancel: AttachCancel())
        let prepared = try #require(preparedOrNil)

        #expect(throws: Boom.self) {
            try TakeSession(
                show: prepared.show, folders: deviceFolders, drive: nil, metadata: metadata, stems: stems, info: info, capture: capture,
                makeStem: { _, _, _ in throw Boom() }, freeSpace: { _ in .max }, preparedDrive: prepared)
        }

        #expect(!FileManager.default.fileExists(atPath: prepared.folder.path))
        #expect(released.n == 1)
    }
}

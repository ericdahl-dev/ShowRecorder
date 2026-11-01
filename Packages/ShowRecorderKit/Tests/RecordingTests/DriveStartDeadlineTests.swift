import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Synchronization
import TakeFile
import Testing

/// Pressing Take no longer waits on the Drive on the main actor (#914): the Drive's folders and Stems are made on a thread
/// of its own, and the Take waits for them at most `driveStartDeadline`. A Drive that is slower starts the Take on the
/// Device alone, as one with no Drive at the press, and joins when it is ready.
@MainActor
@Suite("Take start and the Drive's deadline")
struct DriveStartDeadlineTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "DriveStartDeadlineTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    /// Notes where the Drive's Stems were made, and holds their creation on a gate when asked.
    final class Creation: @unchecked Sendable {
        private let lock = NSLock()
        private var onMain = 0
        private var offMain = 0
        private var began = false
        private var asked = 0
        let gate = TestGate()
        var holds = false
        /// The Drive's answer (the access) waits on the gate: a stick slow to answer.
        var holdsAccess = false
        func askedForDrive() { lock.withLock { asked += 1 } }
        var accessCalls: Int { lock.withLock { asked } }
        func made() { lock.withLock { if Thread.isMainThread { onMain += 1 } else { offMain += 1 } } }
        func enteredDrive() { lock.withLock { began = true } }
        var driveStemsOnMain: Int { lock.withLock { onMain } }
        var driveStemsOffMain: Int { lock.withLock { offMain } }
        var hasBegun: Bool { lock.withLock { began } }
    }

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorder(_ creation: Creation, deadline: Duration, driveOnly: Bool = false) -> Recorder {
        let drive = drive
        let recorder = Recorder(
            deviceFolder: device, driveFolder: {
                creation.askedForDrive()
                if creation.holdsAccess { creation.gate.wait() }
                return DriveAccess(folder: drive)
            }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                if url.path.hasPrefix(drive.path) {
                    creation.made()
                    creation.enteredDrive()
                    if creation.holds { creation.gate.wait() }
                }
                return try StemWriter.open(url: url, info: info, resumingAt: resuming)
            }, destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300), driveStartDeadline: deadline)
        recorder.recordTo = driveOnly ? .drive : .standard
        return recorder
    }

    @Test("With a Drive that answers in time, the Take starts with the Drive and its Stems were made off the main thread")
    func healthyDriveStartsWithTheDrive() async throws {
        let creation = Creation()
        let recorder = recorder(creation, deadline: .seconds(60))
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))

        try await recorder.startTakeOffMain()

        #expect(recorder.isRecording)
        #expect(recorder.session?.copies.map(\.kind) == [.device, .drive])
        #expect(creation.driveStemsOffMain == 1)
        #expect(creation.driveStemsOnMain == 0)
        #expect(recorder.driveNotice == nil)
        try await recorder.stopTake()
    }

    static let tooSlow = "The Drive was too slow to start the Take, so this Take started on the Device only."

    @Test("A Drive slower than the deadline starts the Take on the Device at once, and says why")
    func slowDriveStartsOnTheDevice() async throws {
        let creation = Creation()
        creation.holds = true
        defer { creation.gate.open() }
        let recorder = recorder(creation, deadline: .milliseconds(30))
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))

        try await recorder.startTakeOffMain()

        #expect(recorder.isRecording)
        #expect(!recorder.isStarting)
        #expect(recorder.session?.copies.map(\.kind) == [.device])
        #expect(recorder.driveNotice == Self.tooSlow)
        #expect(recorder.session?.metadata.driveNote == Self.tooSlow, "and Take.json says why")
        #expect(creation.driveStemsOnMain == 0)
        creation.gate.open()
        await recorder.waitForDriveStartJob()
        try await recorder.stopTake()
    }

    @Test("While the first job waits on the Drive's answer no second one is started; once it is done, the Drive joins")
    func lateJoinWaitsForTheCanceledJob() async throws {
        let creation = Creation()
        creation.holdsAccess = true
        defer { creation.gate.open() }
        let recorder = recorder(creation, deadline: .milliseconds(30))
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))
        try await recorder.startTakeOffMain()
        let takeOnDrive = drive.appending(path: "\(recorder.currentShow!.name)/Take 01")
        #expect(recorder.session?.copies.map(\.kind) == [.device])

        // The stick is still answering: a check must not start a second job on the same Take folder.
        await recorder.checkDestinations()
        #expect(recorder.session?.copies.map(\.kind) == [.device], "no join while the first job runs")
        #expect(creation.accessCalls == 1, "and the Drive was not asked a second time")

        creation.gate.open()
        await recorder.waitForDriveStartJob()
        #expect(!FileManager.default.fileExists(atPath: takeOnDrive.path), "the canceled job made nothing")

        await recorder.checkDestinations()
        #expect(recorder.session?.copies.map(\.kind) == [.device, .drive], "then the Drive joins, as it does after a Take with no Drive at the press")
        #expect(creation.accessCalls == 2)
        try await recorder.stopTake()
    }

    @Test("With a Drive only setting and a Drive in time, the Device stands by: nothing of the Take is on it")
    func driveOnlyKeepsTheStandby() async throws {
        let creation = Creation()
        let recorder = recorder(creation, deadline: .seconds(60), driveOnly: true)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)

        try await recorder.startTakeOffMain()
        try await deliverBlocks(5, to: audio, recorder, sample: { _, _ in 0.25 })
        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(!FileManager.default.fileExists(atPath: device.appending(path: "\(recorder.currentShow!.name)/Take 01").path), "no Take folder on the Device")
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "\(recorder.currentShow!.name)/Take 01/01 USB 01.wav").path))
    }

    @Test("A Take with no Drive set up starts at once on the Device and says there was none; no job runs")
    func noDriveConfigured() async throws {
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil,
            driveStartDeadline: .seconds(60))
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))

        try await recorder.startTakeOffMain()

        #expect(recorder.isRecording)
        #expect(recorder.session?.copies.map(\.kind) == [.device])
        #expect(recorder.session?.metadata.driveNote == "No Drive was connected at the press.")
        #expect(recorder.driveNotice == nil)
        try await recorder.stopTake()
    }

    @Test("Standing down while the Drive is being prepared ends the start: nothing of the Take is left on the Device or the Drive")
    func stoodDownWhileStarting() async throws {
        let creation = Creation()
        creation.holds = true
        defer { creation.gate.open() }
        let recorder = recorder(creation, deadline: .seconds(60))
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))

        let starting = Task { @MainActor in try await recorder.startTakeOffMain() }
        let deadline = ContinuousClock.now + .seconds(60)
        while !creation.hasBegun, ContinuousClock.now < deadline { await Task.yield() }
        #expect(recorder.isStarting)
        // Nothing else may change the Show or start a second Take meanwhile.
        #expect(throws: RecorderError.self) { try recorder.startNewShow(name: "Other", venue: "") }
        try await recorder.startTakeOffMain()
        #expect(!recorder.isRecording, "a second press while one is starting does nothing")
        recorder.standDown()
        creation.gate.open()

        await #expect(throws: RecorderError.self) { try await starting.value }
        #expect(!recorder.isStarting)
        #expect(!recorder.isRecording)
        let show = try #require(recorder.currentShow).name
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: "\(show)/Take 01").path))
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/Take 01").path))
    }

    /// Starts a Take that waits on the Drive's answer, and returns once the job is inside that wait.
    func startingWhileTheDriveAnswers(_ recorder: Recorder, _ creation: Creation) async -> Task<Void, any Error> {
        let starting = Task { @MainActor in try await recorder.startTakeOffMain() }
        let deadline = ContinuousClock.now + .seconds(60)
        while creation.accessCalls == 0, ContinuousClock.now < deadline { await Task.yield() }
        return starting
    }

    @Test("Record to changed while the Drive is being prepared: the Take is the one the press decided, not a crash")
    func recordToChangesDuringTheStart() async throws {
        let creation = Creation()
        creation.holdsAccess = true
        defer { creation.gate.open() }
        let recorder = recorder(creation, deadline: .seconds(60))
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))

        let starting = await startingWhileTheDriveAnswers(recorder, creation)
        recorder.recordTo = .device
        creation.gate.open()
        try await starting.value

        #expect(recorder.session?.copies.map(\.kind) == [.device, .drive], "the press chose Both")
        try await recorder.stopTake()
    }

    @Test("A gain change made while the Take is starting is kept in the Show, in memory and in Show.json on the Device")
    func gainChangeDuringTheStart() async throws {
        let creation = Creation()
        creation.holdsAccess = true
        defer { creation.gate.open() }
        let recorder = recorder(creation, deadline: .seconds(60))
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))

        let starting = await startingWhileTheDriveAnswers(recorder, creation)
        recorder.logGainChange(TakeMetadata.GainChange(usbChannel: 1, channel: 1, headamp: 1, fromGainDb: 14.5, toGainDb: 11.5, reason: .clipProtection, compensations: []))
        creation.gate.open()
        try await starting.value

        let show = try #require(recorder.currentShow)
        #expect(show.gainChanges.count == 1, "in memory")
        let onDevice = try #require(ShowFile.read(from: show.folder))
        #expect(onDevice.gainChanges?.count == 1, "and in Show.json on the Device")
        #expect(onDevice.takes == 1, "with the Take number the Take has")
        try await recorder.stopTake()
    }

    @Test("A Drive only Take's Drive Take.json says Drive only from the start")
    func driveOnlyFlagOnTheDrive() async throws {
        let creation = Creation()
        let recorder = recorder(creation, deadline: .seconds(60), driveOnly: true)
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))

        try await recorder.startTakeOffMain()

        let onDrive = try TakeMetadata.read(fromTakeFolder: drive.appending(path: "\(recorder.currentShow!.name)/Take 01"))
        #expect(onDrive.driveOnly == true)
        try await recorder.stopTake()
    }

    @Test("A Free Take, which may not use the Drive, never asks for it")
    func freeTakeNeverAsks() async throws {
        let creation = Creation()
        let recorder = recorder(creation, deadline: .seconds(60))
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 1))

        try await recorder.startTakeOffMain(allowance: { var free = Entitlement.allowance(for: .free, channelCount: 1); free.driveCopy = false; return free }())

        #expect(recorder.session?.copies.map(\.kind) == [.device])
        #expect(!creation.hasBegun)
        #expect(recorder.driveNotice == "The Drive Copy is a Pro feature.")
        try await recorder.stopTake()
    }
}

/// The meeting point of the job and the deadline (#914).
@MainActor
@Suite("Drive start handoff")
struct DriveStartHandoffTests {
    func prepared() throws -> TakeSession.PreparedDrive {
        let root = FileManager.default.temporaryDirectory.appending(path: "DriveStartHandoffTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
        var show = try Show.create(in: root.appending(path: "Device"), drive: nil, on: RecordingTakeTests.showDay)
        _ = try show.createNextTakeFolder()
        let metadata = TakeMetadata(
            show: show.name, take: show.takeCount, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "ShowRecorder", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        let drive = root.appending(path: "Drive")
        let result = TakeSession.prepareDriveStart(
            show: show, metadata: metadata, stems: [StemSpec(file: "01 USB 01.wav", description: "USB 01")], info: info,
            makeStem: { try StemWriter.open(url: $0, info: $1, resumingAt: $2) }, freeSpace: { _ in .max },
            drive: { DriveAccess(folder: drive) }, cancel: AttachCancel())
        return try #require(result)
    }

    @Test("A job that finishes first is what the Take gets, and a deadline after it changes nothing")
    func jobFirst() async throws {
        let handoff = DriveStartHandoff()
        let made = try prepared()
        #expect(handoff.finish(.init(prepared: made, noDrive: false, problem: nil)) == nil)
        handoff.timeOut()
        guard case .finished(let finished) = await handoff.wait() else { Issue.record("expected the job's result"); return }
        #expect(finished.prepared?.folder == made.folder)
        TakeSession.discardDriveStart(made)
    }

    @Test("A job that finishes after the deadline is handed back to discard what it made, and the Take got the deadline")
    func deadlineFirst() async throws {
        let handoff = DriveStartHandoff()
        let made = try prepared()
        handoff.timeOut()
        guard case .timedOut = await handoff.wait() else { Issue.record("expected the deadline"); return }
        let handedBack = handoff.finish(.init(prepared: made, noDrive: false, problem: nil))
        #expect(handedBack?.folder == made.folder, "for the job to discard")
        TakeSession.discardDriveStart(made)
    }
}

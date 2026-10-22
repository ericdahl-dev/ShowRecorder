import AudioIO
import Destinations
import Foundation
import Synchronization
@testable import Recording
import Testing

/// The names typed during a Take are put on its files after Stop, on the Drive too (#652): that renames Stems and rewrites
/// Take.json, so it runs off the main thread.
@MainActor
@Suite("Naming a Take's files off the main thread")
struct NameChannelsOffMainTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "NameChannelsOffMainTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    @Test("A name typed during the Take is put on the Stems off the main thread, and still lands on every Copy")
    func renameOffMain() async throws {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
                                destinationCheckInterval: nil, asyncStopAvailable: { true })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        let threads = Mutex<[Bool]>([])
        let real = recorder.renameChannels
        recorder.renameChannels = { names, late, copies, extras in
            threads.withLock { $0.append(Thread.isMainThread) }
            real(names, late, copies, extras)
        }
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        recorder.setChannelName("Kick", forChannel: 1)

        try await recorder.stopTake()
        await recorder.waitForRepair()

        #expect(threads.withLock { $0 } == [false])
        for copy in [device, drive] {
            let names = try FileManager.default.contentsOfDirectory(atPath: copy.appending(path: "2026-10-06 Show/Take 01").path)
            #expect(names.contains { $0.hasSuffix("Kick.wav") }, "\(copy.lastPathComponent): \(names)")
        }
    }

    @Test("While the names are being put on the files, the Take can't be deleted from under it, and the main thread is free")
    func deleteRefusedWhileRenaming() async throws {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
                                destinationCheckInterval: nil, asyncStopAvailable: { true })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        let gate = DispatchSemaphore(value: 0)
        let entered = Mutex(false)
        recorder.renameChannels = { _, _, _, _ in
            entered.withLock { $0 = true }
            _ = gate.wait(timeout: .now() + 60)
        }
        defer { gate.signal() }
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.2, count: 4_800)])
        recorder.setChannelName("Kick", forChannel: 1)
        try await recorder.stopTake()

        try await waitUntil { entered.withLock { $0 } }   // the rename is under way, held
        try recorder.endShow()   // an open Show is refused for its own reason: end it, so only the rename is in the way
        let outcome = recorder.deleteTake(1, ofShow: "2026-10-06 Show", from: [.device, .drive])

        #expect(outcome.deleted.isEmpty && outcome.failed.contains { $0.reason.contains("renamed") }, "\(outcome)")
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 01").path))
        gate.signal()
        await recorder.waitForRepair()
        let after = recorder.deleteTake(1, ofShow: "2026-10-06 Show", from: [.device])
        #expect(after.deleted == [.device], "and once it is done, the delete goes through: \(after)")
    }
}

import AudioIO
import Foundation
import MixerLink
@testable import Recording
import Testing

@MainActor
@Suite("Both Destinations")
struct BothDestinationsTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "BothDestinationsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// Every file under `folder`, relative path → contents.
    func contents(of folder: URL) throws -> [String: Data] {
        let base = folder.resolvingSymlinksInPath().path
        let enumerator = FileManager.default.enumerator(at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey])!
        var files: [String: Data] = [:]
        for case let url as URL in enumerator where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            files[String(url.resolvingSymlinksInPath().path.dropFirst(base.count))] = try Data(contentsOf: url)
        }
        return files
    }

    @Test("Each Take is written to the Device and the Drive as byte-identical Copies")
    func copiesAreByteIdentical() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 4)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)

        for take in 0..<2 {
            try recorder.startTake(sources: [Source(name: "Kick", color: .off)])
            for block in 0..<100 {
                audio.deliver((0..<4).map { channel in (0..<480).map { Float(channel * 100_000 + take * 50_000 + block * 480 + $0) / 8_388_608 } })
                while recorder.bufferedFrameCount > 48_000 { try await Task.sleep(for: .milliseconds(2)) }
            }
            try recorder.stopTake()
        }

        let deviceCopy = try contents(of: device)
        let driveCopy = try contents(of: drive)
        #expect(deviceCopy.keys.contains("/2026-10-06 Show/Take 01/01 Kick.wav"))
        #expect(deviceCopy.keys.contains("/2026-10-06 Show/Take 02/04 USB 04.wav"))
        #expect(deviceCopy.keys.sorted() == driveCopy.keys.sorted())
        for (path, data) in deviceCopy {
            #expect(driveCopy[path] == data, "\(path) differs between the Copies")
        }
    }

    @Test("Without a Drive folder, the Take is written to the Device only")
    func noDriveWritesDeviceOnly() throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)

        try recorder.startTake()
        audio.deliver([[0]])
        try recorder.stopTake()

        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 01/01 USB 01.wav").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: drive.path).isEmpty)
    }

    @Test("A Drive that appears mid-Show gets the same Show folder, from the next Take on")
    func driveAppearingMidShowJoinsNextTake() throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let available = DriveSwitch()
        let recorder = Recorder(deviceFolder: device, driveFolder: { available.folder.map { DestinationAccess(folder: $0) } }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)

        try recorder.startTake()
        audio.deliver([[0]])
        try recorder.stopTake()
        available.folder = drive
        try recorder.startTake()
        audio.deliver([[0]])
        try recorder.stopTake()

        let driveShow = drive.appending(path: "2026-10-06 Show")
        #expect(!FileManager.default.fileExists(atPath: driveShow.appending(path: "Take 01").path))
        #expect(FileManager.default.fileExists(atPath: driveShow.appending(path: "Take 02/01 USB 01.wav").path))
    }

    @Test("A Show name already used on the Drive isn't reused on either Copy")
    func showNameTakenOnDriveIsSkipped() throws {
        try FileManager.default.createDirectory(at: drive.appending(path: "2026-10-06 Show"), withIntermediateDirectories: true)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)

        try recorder.startTake()
        try recorder.stopTake()

        #expect(recorder.currentShow?.name == "2026-10-06 Show 2")
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show 2/Take 01").path))
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "2026-10-06 Show 2/Take 01").path))
    }

    @Test("The Drive folder is released when the Take stops")
    func driveAccessReleasedAtStop() throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let released = ReleaseCounter()
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive, release: { released.count += 1 }) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)

        try recorder.startTake()
        #expect(released.count == 0)
        try recorder.stopTake()

        #expect(released.count == 1)
    }
}

@MainActor
final class DriveSwitch {
    var folder: URL?
}

@MainActor
final class ReleaseCounter {
    var count = 0
}

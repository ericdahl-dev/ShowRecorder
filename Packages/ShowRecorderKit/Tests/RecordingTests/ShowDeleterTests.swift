import AudioIO
import Destinations
import Foundation
import Testing

@testable import Recording

/// Deleting a whole Show from the Device, the Drive or both. Permanent, so it only ever removes one named
/// Show folder per chosen Copy.
@MainActor
@Suite("Delete a Show")
struct ShowDeleterTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    @MainActor final class Clock { var now = RecordingTakeTests.showDay }
    let clock = Clock()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShowDeleterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorder() -> Recorder {
        let clock = clock, drive = drive
        return Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { MainActor.assumeIsolated { clock.now } })
    }

    /// Records one Take in "2026-10-06 Show", ends it, then records another Show a day later (left open).
    func twoShows(_ recorder: Recorder) throws {
        func record() throws {
            let audio = FakeAudioDevice(inputChannelCount: 1)
            try recorder.arm(audio)
            try recorder.startTake()
            audio.deliver([[0.1]])
            try recorder.stopTake()
            recorder.disarm()
        }
        try record()
        try recorder.endShow()
        clock.now = clock.now.addingTimeInterval(24 * 3600)
        try record()
    }

    func exists(_ parent: URL, _ show: String) -> Bool {
        FileManager.default.fileExists(atPath: parent.appending(path: show).path)
    }

    @Test("Deleting from both Copies removes that Show's folder from the Device and the Drive, and no other Show")
    func bothCopies() throws {
        try twoShows(recorder())

        let outcome = ShowDeleter.delete(show: "2026-10-06 Show", from: [.device, .drive], device: device, drive: drive, openShow: "2026-10-07 Show")

        #expect(outcome.deleted == [.device, .drive])
        #expect(outcome.failed.isEmpty)
        #expect(!exists(device, "2026-10-06 Show") && !exists(drive, "2026-10-06 Show"))
        #expect(exists(device, "2026-10-07 Show") && exists(drive, "2026-10-07 Show"), "the other Show is untouched")
    }

    @Test("Device only leaves the Drive Copy, and a Drive that isn't there is reported and not touched")
    func oneCopyAndMissingDrive() throws {
        try twoShows(recorder())

        let deviceOnly = ShowDeleter.delete(show: "2026-10-06 Show", from: [.device], device: device, drive: drive, openShow: nil)
        #expect(deviceOnly.deleted == [.device])
        #expect(!exists(device, "2026-10-06 Show") && exists(drive, "2026-10-06 Show"))

        let noDrive = ShowDeleter.delete(show: "2026-10-07 Show", from: [.device, .drive], device: device, drive: nil, openShow: nil)
        #expect(noDrive.deleted == [.device])
        #expect(noDrive.failed.map(\.copy) == [.drive])
        #expect(exists(drive, "2026-10-07 Show"), "the Drive Copy is untouched")
    }

    @Test("The open Show is refused, and nothing is deleted")
    func openShowRefused() throws {
        try twoShows(recorder())

        let outcome = ShowDeleter.delete(show: "2026-10-07 Show", from: [.device, .drive], device: device, drive: drive, openShow: "2026-10-07 Show")

        #expect(outcome.deleted.isEmpty)
        #expect(outcome.failed.map(\.copy) == [.device, .drive])
        #expect(exists(device, "2026-10-07 Show") && exists(drive, "2026-10-07 Show"))
    }

    @Test("A name that isn't one Show folder directly inside the Shows folder is refused", arguments: ["", ".", "..", "a/b", "../Drive", "2026-10-06 Show/Take 01", ".hidden"])
    func unsafeNamesRefused(name: String) throws {
        try twoShows(recorder())
        try FileManager.default.createDirectory(at: device.appending(path: ".hidden"), withIntermediateDirectories: true)

        let outcome = ShowDeleter.delete(show: name, from: [.device, .drive], device: device, drive: drive, openShow: nil)

        #expect(outcome.deleted.isEmpty)
        #expect(exists(device, "2026-10-06 Show/Take 01") && exists(drive, "2026-10-06 Show/Take 01"))
        #expect(exists(root, "Drive") && exists(root, "Device"))
        #expect(exists(device, ".hidden"))
    }

    @Test("A folder that isn't a Show (no Show.json, no Take folders) is refused")
    func notAShowRefused() throws {
        try twoShows(recorder())
        try FileManager.default.createDirectory(at: device.appending(path: "Holiday photos"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: device.appending(path: "Holiday photos/a.jpg"))

        let outcome = ShowDeleter.delete(show: "Holiday photos", from: [.device], device: device, drive: drive, openShow: nil)

        #expect(outcome.deleted.isEmpty)
        #expect(exists(device, "Holiday photos/a.jpg"))
    }

    @Test("Typing the Show's name confirms; anything else, including a different case or extra space, does not")
    func confirmation() {
        #expect(ShowDeleter.confirms(typed: "2026-10-06 Show", for: "2026-10-06 Show"))
        #expect(!ShowDeleter.confirms(typed: "2026-10-06 show", for: "2026-10-06 Show"))
        #expect(!ShowDeleter.confirms(typed: "2026-10-06 Show ", for: "2026-10-06 Show"))
        #expect(!ShowDeleter.confirms(typed: "", for: ""))
    }

    @Test("A link named like a Show is never followed: what it points at is untouched")
    func symlinkNotFollowed() throws {
        let recorder = recorder()
        try twoShows(recorder)
        try FileManager.default.createSymbolicLink(at: device.appending(path: "2026-10-01 Linked"), withDestinationURL: drive.appending(path: "2026-10-06 Show"))

        let outcome = ShowDeleter.delete(show: "2026-10-01 Linked", from: [.device], device: device, drive: nil, openShow: nil)

        #expect(outcome.deleted.isEmpty)
        #expect(exists(drive, "2026-10-06 Show/Take 01"), "the target is untouched")
    }

    @Test("The recorder refuses while a Take is running and for the open Show, and deletes through the Drive when it is there")
    func recorderDelete() throws {
        let recorder = recorder()
        try twoShows(recorder)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        #expect(recorder.deleteShow(named: "2026-10-06 Show", from: [.device, .drive]).deleted.isEmpty, "during a Take")
        try recorder.stopTake()

        #expect(recorder.deleteShow(named: "2026-10-07 Show", from: [.device]).deleted.isEmpty, "the open Show")
        let outcome = recorder.deleteShow(named: "2026-10-06 Show", from: [.device, .drive])
        #expect(outcome.deleted == [.device, .drive])
        #expect(!exists(device, "2026-10-06 Show") && !exists(drive, "2026-10-06 Show"))
    }
}

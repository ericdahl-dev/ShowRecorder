import AudioIO
import Destinations
import Foundation
import Testing

@testable import Recording

/// Deleting one Take of a Show from the Device, the Drive or both. Permanent.
@MainActor
@Suite("Delete a Take")
struct TakeDeleterTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let show = "2026-10-06 Show"

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "TakeDeleterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// Three Takes in an ended Show, in both Copies.
    func threeTakes() throws -> Recorder {
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        for _ in 1...3 {
            try recorder.startTake()
            audio.deliver([[0.1]])
            try recorder.stopTake()
        }
        recorder.disarm()
        try recorder.endShow()
        return recorder
    }

    func exists(_ parent: URL, _ path: String) -> Bool { FileManager.default.fileExists(atPath: parent.appending(path: path).path) }

    @Test("Deleting Take 2 from both Copies leaves Takes 1 and 3 with their numbers, and the report and Reaper project no longer list it")
    func takeGoesOthersStay() throws {
        _ = try threeTakes()

        let outcome = TakeDeleter.delete(take: 2, ofShow: show, from: [.device, .drive], device: device, drive: drive, openShow: nil)

        #expect(outcome.deleted == [.device, .drive])
        for parent in [device, drive] {
            #expect(!exists(parent, "\(show)/Take 02"))
            #expect(exists(parent, "\(show)/Take 01/Take.json") && exists(parent, "\(show)/Take 03/Take.json"))
            let report = try String(contentsOf: parent.appending(path: "\(show)/Report.html"), encoding: .utf8)
            #expect(!report.contains("Take 02") && report.contains("Take 03"))
            let project = try String(contentsOf: parent.appending(path: "\(show)/\(show).rpp"), encoding: .utf8)
            #expect(!project.contains("Take 02/") && project.contains("Take 03/"))
        }
    }

    @Test("One Copy only, and a Drive that isn't there is reported and not touched")
    func oneCopyAndMissingDrive() throws {
        _ = try threeTakes()
        let deviceOnly = TakeDeleter.delete(take: 1, ofShow: show, from: [.device], device: device, drive: drive, openShow: nil)
        #expect(deviceOnly.deleted == [.device])
        #expect(!exists(device, "\(show)/Take 01") && exists(drive, "\(show)/Take 01"))

        let noDrive = TakeDeleter.delete(take: 3, ofShow: show, from: [.device, .drive], device: device, drive: nil, openShow: nil)
        #expect(noDrive.deleted == [.device])
        #expect(noDrive.failed.map(\.copy) == [.drive])
        #expect(exists(drive, "\(show)/Take 03"))
    }

    @Test("The open Show, a Take that isn't there, an unsafe Show name and a Take folder with no Take.json are all refused, deleting nothing")
    func refusals() throws {
        _ = try threeTakes()
        try FileManager.default.createDirectory(at: device.appending(path: "\(show)/Take 09"), withIntermediateDirectories: true)

        for (take, name, open) in [(1, show, show), (7, show, nil), (0, show, nil), (9, show, nil), (1, "../Drive", nil), (1, "", nil)] as [(Int, String, String?)] {
            let outcome = TakeDeleter.delete(take: take, ofShow: name, from: [.device, .drive], device: device, drive: drive, openShow: open)
            #expect(outcome.deleted.isEmpty, "\(name) Take \(take)")
        }
        for n in 1...3 { #expect(exists(device, "\(show)/Take 0\(n)/Take.json") && exists(drive, "\(show)/Take 0\(n)/Take.json")) }
        #expect(exists(device, "\(show)/Take 09"))
    }

    @Test("Deleting the last Take of a Show leaves the Show folder, with no Takes")
    func lastTake() throws {
        _ = try threeTakes()
        for n in 1...3 { _ = TakeDeleter.delete(take: n, ofShow: show, from: [.device], device: device, drive: nil, openShow: nil) }
        #expect(exists(device, "\(show)/Show.json"))
        #expect(!exists(device, "\(show)/Take 01") && !exists(device, "\(show)/Take 03"))
    }

    @Test("The recorder refuses during a Take and for the open Show, and deletes through the Drive when it is there")
    func recorderDelete() throws {
        let recorder = try threeTakes()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()   // a new Show, now open and recording
        #expect(recorder.deleteTake(2, ofShow: show, from: [.device, .drive]).deleted.isEmpty, "during a Take")
        try recorder.stopTake()
        let open = try #require(recorder.currentShow?.name)
        #expect(recorder.deleteTake(1, ofShow: open, from: [.device]).deleted.isEmpty, "the open Show")

        #expect(recorder.deleteTake(2, ofShow: show, from: [.device, .drive]).deleted == [.device, .drive])
        #expect(!exists(drive, "\(show)/Take 02"))
    }
}

import AudioIO
import Destinations
import Foundation
import Testing

@testable import Recording

/// Starting a Show on purpose, with a name and a venue.
@MainActor
@Suite("New Show")
struct NewShowTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "NewShowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    func recorder(withDrive: Bool = false) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { withDrive ? DestinationAccess(folder: drive) : nil },
            now: { RecordingTakeTests.showDay })
    }

    func record(_ recorder: Recorder) throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.1, count: 480)])
        try recorder.stopTake()
        recorder.disarm()
    }

    @Test("New Show makes \"YYYY-MM-DD Name\" with the venue in Show.json, ends the old Show, and the next Take lands in it")
    func newShowWithNameAndVenue() throws {
        let recorder = recorder()
        try record(recorder)
        #expect(recorder.currentShow?.name == "2026-10-06 Show")

        try recorder.startNewShow(name: "Sunday Service", venue: "Grace Church")
        #expect(recorder.currentShow?.name == "2026-10-06 Sunday Service")
        let file = try #require(ShowFile.read(from: device.appending(path: "2026-10-06 Sunday Service")))
        #expect(file.venue == "Grace Church")
        #expect(file.endedAt == nil)
        #expect(ShowFile.read(from: device.appending(path: "2026-10-06 Show"))?.endedAt != nil, "the old Show is ended")

        try record(recorder)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Sunday Service/Take 01").path))
    }

    @Test("A blank name gives \"Show\", a repeated name gets \" 2\", and slashes, colons and leading dots are made safe, never refused")
    func namesAreMadeSafe() throws {
        let recorder = recorder()
        try recorder.startNewShow(name: "   ", venue: "")
        #expect(recorder.currentShow?.name == "2026-10-06 Show")
        #expect(recorder.currentShow?.venue == nil, "a blank venue is none")
        try recorder.startNewShow(name: "Sunday", venue: "")
        try recorder.startNewShow(name: " Sunday ", venue: "")
        #expect(recorder.currentShow?.name == "2026-10-06 Sunday 2")
        try recorder.startNewShow(name: "A/B: Gig", venue: "")
        #expect(recorder.currentShow?.name == "2026-10-06 A-B- Gig")
        try recorder.startNewShow(name: "..hidden", venue: "")
        #expect(recorder.currentShow?.name == "2026-10-06 hidden")
        #expect(try FileManager.default.contentsOfDirectory(atPath: device.path).filter { !$0.hasPrefix("2026-10-06 ") }.isEmpty)
    }

    @Test("It can't start a Show while a Take is running, and leaves everything as it was")
    func refusedWhileRecording() throws {
        let recorder = recorder()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        #expect(throws: RecorderError.takeRunning) { try recorder.startNewShow(name: "Late", venue: "") }
        #expect(recorder.currentShow?.name == "2026-10-06 Show")
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Late").path))
        try recorder.stopTake()
        #expect(ShowFile.read(from: device.appending(path: "2026-10-06 Show"))?.endedAt == nil)
    }

    @Test("With a Drive, the Drive Copy of the new Show has its Show.json, with the venue, once a Take starts")
    func driveCopyHasTheVenue() throws {
        let recorder = recorder(withDrive: true)
        try recorder.startNewShow(name: "Gig", venue: "The Hall")
        try record(recorder)
        let file = try #require(ShowFile.read(from: drive.appending(path: "2026-10-06 Gig")))
        #expect(file.venue == "The Hall" && file.name == "2026-10-06 Gig")
    }
}

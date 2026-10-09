import AudioIO
import Destinations
import Foundation
import Testing

@testable import Recording

/// Deleting one channel's file from a Take, in the Copies chosen. Permanent.
@MainActor
@Suite("Delete a channel's file")
struct StemDeleterTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let show = "2026-10-06 Show"

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "StemDeleterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// One Take of 3 channels in an ended Show, in both Copies.
    func record() throws -> Recorder {
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 3)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([[0.1], [0.1], [0.1]])
        try recorder.stopTake()
        recorder.disarm()
        try recorder.endShow()
        return recorder
    }

    func exists(_ parent: URL, _ path: String) -> Bool { FileManager.default.fileExists(atPath: parent.appending(path: path).path) }

    func channels(_ parent: URL) throws -> [Int] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: Data(contentsOf: parent.appending(path: "\(show)/Take 01/Take.json"))).usbChannels.map(\.usbChannel)
    }

    @Test("Deleting channel 2 removes its file and its Take.json entry in both Copies, leaves channels 1 and 3, and drops it from the report and Reaper project")
    func channelGoes() throws {
        _ = try record()

        let outcome = StemDeleter.delete(channel: 2, inTake: 1, ofShow: show, from: [.device, .drive], device: device, drive: drive, openShow: nil)

        #expect(outcome.deleted == [.device, .drive])
        for parent in [device, drive] {
            #expect(!exists(parent, "\(show)/Take 01/02 USB 02.wav"))
            #expect(exists(parent, "\(show)/Take 01/01 USB 01.wav") && exists(parent, "\(show)/Take 01/03 USB 03.wav"))
            #expect(try channels(parent) == [1, 3])
            let project = try String(contentsOf: parent.appending(path: "\(show)/\(show).rpp"), encoding: .utf8)
            #expect(!project.contains("02 USB 02.wav") && project.contains("03 USB 03.wav"))
        }
    }

    @Test("Device only keeps the channel on the Drive; a later Marker rename and channel rename still work on the Copy that lacks it")
    func oneCopyThenRename() throws {
        let recorder = try record()
        _ = StemDeleter.delete(channel: 2, inTake: 1, ofShow: show, from: [.device], device: device, drive: drive, openShow: nil)
        #expect(try channels(device) == [1, 3] && channels(drive) == [1, 2, 3])
        #expect(exists(drive, "\(show)/Take 01/02 USB 02.wav"))

        let copies: [DestinationKind: URL] = [.device: device.appending(path: "\(show)/Take 01"), .drive: drive.appending(path: "\(show)/Take 01")]
        let named = ChannelRenamer.rename(names: [2: "Bass", 3: "Keys"], in: copies)
        #expect(named.renamed == [.device, .drive] && named.failed.isEmpty)
        #expect(exists(device, "\(show)/Take 01/03 Keys.wav") && !exists(device, "\(show)/Take 01/02 Bass.wav"))
        #expect(exists(drive, "\(show)/Take 01/02 Bass.wav"))
        _ = recorder
    }

    @Test("Refused: open Show, a channel that isn't there, an unsafe name or Take; a Drive that isn't there is reported")
    func refusals() throws {
        _ = try record()
        for (channel, take, name, open) in [(2, 1, show, show), (9, 1, show, nil), (0, 1, show, nil), (2, 5, show, nil), (2, 1, "../Drive", nil)] as [(Int, Int, String, String?)] {
            let outcome = StemDeleter.delete(channel: channel, inTake: take, ofShow: name, from: [.device, .drive], device: device, drive: drive, openShow: open)
            #expect(outcome.deleted.isEmpty, "\(name) take \(take) channel \(channel)")
        }
        #expect(try channels(device) == [1, 2, 3] && channels(drive) == [1, 2, 3])

        let noDrive = StemDeleter.delete(channel: 3, inTake: 1, ofShow: show, from: [.device, .drive], device: device, drive: nil, openShow: nil)
        #expect(noDrive.deleted == [.device] && noDrive.failed.map(\.copy) == [.drive])
        #expect(try channels(drive) == [1, 2, 3])
    }

    @Test("The recorder refuses during a Take and for the open Show")
    func recorderDelete() throws {
        let recorder = try record()
        let audio = FakeAudioDevice(inputChannelCount: 3)
        try recorder.arm(audio)
        try recorder.startTake()
        #expect(recorder.deleteChannel(2, inTake: 1, ofShow: show, from: [.device]).deleted.isEmpty, "during a Take")
        try recorder.stopTake()
        let open = try #require(recorder.currentShow?.name)
        #expect(recorder.deleteChannel(1, inTake: 1, ofShow: open, from: [.device]).deleted.isEmpty, "the open Show")
        #expect(recorder.deleteChannel(2, inTake: 1, ofShow: show, from: [.device, .drive]).deleted == [.device, .drive])
    }
}

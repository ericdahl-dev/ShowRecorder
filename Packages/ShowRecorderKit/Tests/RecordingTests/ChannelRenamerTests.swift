import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

/// Naming a channel by hand after the Take, from the files on disk.
@MainActor
@Suite("Renaming a channel from files")
struct ChannelRenamerTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    func take(_ copy: URL) -> URL { copy.appending(path: "2026-10-06 Show/Take 01") }
    var copies: [DestinationKind: URL] { [.device: take(device), .drive: take(drive)] }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ChannelRenamerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// Records a Take of 2 channels in both Copies, with a Marker.
    func recordTake() throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver((0..<2).map { channel in (0..<4_800).map { Float($0 % 1000 + channel * 1000) / 8_388_608 } })
        recorder.addMarker()
        audio.deliver((0..<2).map { channel in (0..<480).map { Float($0 % 1000 + channel * 1000) / 8_388_608 } })
        try recorder.stopTake()
    }

    func metadata(_ copy: URL) throws -> TakeMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: Data(contentsOf: copy.appending(path: "Take.json")))
    }

    @Test("Naming a channel renames its Stem, bext description and Take.json in every Copy, and leaves the audio and the other channels as they were")
    func renameOnDisk() throws {
        try recordTake()
        let before = try copies.values.map { try StemFile(contentsOf: $0.appending(path: "02 USB 02.wav")) }

        let outcome = ChannelRenamer.rename(names: [2: "Lead Vocal"], in: copies)

        #expect(outcome.result == .renamed)
        #expect(Set(outcome.renamed) == [.device, .drive])
        #expect(outcome.failed.isEmpty)
        for copy in copies.values {
            #expect(!FileManager.default.fileExists(atPath: copy.appending(path: "02 USB 02.wav").path))
            let stem = try StemFile(contentsOf: copy.appending(path: "02 Lead Vocal.wav"))
            #expect(stem.description == "Lead Vocal")
            #expect(stem.samples == before[0].samples, "the audio is untouched")
            #expect(stem.timeReference == before[0].timeReference)
            #expect(try cuePoints(copy.appending(path: "02 Lead Vocal.wav")).map(\.label) == ["Marker 1"], "its Marker survives")
            let channels = try metadata(copy).usbChannels
            #expect(channels[1].name == "Lead Vocal")
            #expect(channels[1].stemFile == "02 Lead Vocal.wav")
            #expect(channels[1].hasMixerName == false)
            #expect(channels[0].stemFile == "01 USB 01.wav", "the other channel is untouched")
            #expect(try StemFile(contentsOf: copy.appending(path: "01 USB 01.wav")).description == "USB 01")
        }
    }

    @Test("The report and the Reaper project show the new name")
    func reportAndProject() throws {
        try recordTake()
        _ = ChannelRenamer.rename(names: [2: "Lead Vocal"], in: copies)
        for copy in [device, drive] {
            let show = copy.appending(path: "2026-10-06 Show")
            let report = try String(contentsOf: show.appending(path: "Report.html"), encoding: .utf8)
            let project = try String(contentsOf: show.appending(path: "2026-10-06 Show.rpp"), encoding: .utf8)
            #expect(report.contains("Lead Vocal"))
            #expect(project.contains("02 Lead Vocal.wav"))
        }
    }

    @Test("With a Copy not reachable the others are renamed and the outcome names it; an empty name is refused")
    func oneCopyMissingAndEmptyName() throws {
        try recordTake()
        #expect(ChannelRenamer.rename(names: [2: "  "], in: copies).result == .emptyName)
        #expect(FileManager.default.fileExists(atPath: take(device).appending(path: "02 USB 02.wav").path), "nothing changed")

        try FileManager.default.moveItem(at: drive, to: root.appending(path: "Drive (unplugged)"))
        let outcome = ChannelRenamer.rename(names: [1: "Kick"], in: copies)

        #expect(outcome.result == .renamed)
        #expect(outcome.renamed == [.device])
        #expect(outcome.failed.map(\.copy) == [.drive])
        #expect(FileManager.default.fileExists(atPath: take(device).appending(path: "01 Kick.wav").path))
    }

    @Test("A name typed during a Take changes no file until the Take ends; then every Copy has it, and the next Take starts with it")
    func nameDuringTake() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])

        #expect(recorder.setChannelName("  Lead Vocal ", forChannel: 2))
        #expect(!recorder.setChannelName("   ", forChannel: 1), "empty names are refused")
        #expect(recorder.channelNames == [2: "Lead Vocal"])
        #expect(FileManager.default.fileExists(atPath: take(device).appending(path: "02 USB 02.wav").path), "open Stem untouched")

        try recorder.stopTake()
        await recorder.waitForRepair()
        for copy in copies.values {
            #expect(FileManager.default.fileExists(atPath: copy.appending(path: "02 Lead Vocal.wav").path))
            #expect(try metadata(copy).usbChannels[1].name == "Lead Vocal")
        }

        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 02/02 Lead Vocal.wav").path))
        try recorder.stopTake()
        await recorder.waitForRepair()
    }

    func recorder() -> Recorder {
        let drive = drive
        return Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
    }

    @Test("Names typed for the Show come back after a relaunch, and the next Take starts with them")
    func namesSurviveRelaunch() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let first = recorder()
        try first.arm(audio)
        try first.startTake()
        audio.deliver([[0.1], [0.1]])
        first.setChannelName("Lead Vocal", forChannel: 2)
        try first.stopTake()
        await first.waitForRepair()

        let relaunched = recorder()
        #expect(relaunched.channelNames == [2: "Lead Vocal"])
        let audio2 = FakeAudioDevice(inputChannelCount: 2)
        try relaunched.arm(audio2)
        try relaunched.startTake()
        audio2.deliver([[0.1], [0.1]])
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Show/Take 02/02 Lead Vocal.wav").path))
        try relaunched.stopTake()
        await relaunched.waitForRepair()
    }

    @Test("A new Show (New Show or End Show) starts without the old Show's names, and the old Show keeps its own")
    func newShowStartsClean() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let recorder = recorder()
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        recorder.setChannelName("Lead Vocal", forChannel: 2)
        try recorder.stopTake()
        await recorder.waitForRepair()

        try recorder.startNewShow(name: "Late", venue: "")
        #expect(recorder.channelNames.isEmpty)
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(FileManager.default.fileExists(atPath: device.appending(path: "2026-10-06 Late/Take 01/02 USB 02.wav").path))
        #expect(ShowFile.read(from: device.appending(path: "2026-10-06 Show"))?.channelNames == ["2": "Lead Vocal"])

        recorder.setChannelName("Bass", forChannel: 1)
        try recorder.endShow()
        #expect(recorder.channelNames.isEmpty)
    }

    @Test("After 6 idle hours the Show is over, so a name typed then is for the next Show")
    func idleShowDropsNames() async throws {
        final class Clock: @unchecked Sendable { nonisolated(unsafe) var now: Date; init(_ now: Date) { self.now = now } }
        let clock = Clock(RecordingTakeTests.showDay)
        let audio = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: device, now: { clock.now })
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        recorder.setChannelName("Lead Vocal", forChannel: 2)
        try recorder.stopTake()
        await recorder.waitForRepair()

        clock.now = clock.now.addingTimeInterval(7 * 3600)
        recorder.setChannelName("Bass", forChannel: 1)
        #expect(recorder.channelNames == [1: "Bass"])
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        try recorder.stopTake()
        await recorder.waitForRepair()
        let next = try #require(recorder.currentShow)
        #expect(next.name != "2026-10-06 Show")
        #expect(FileManager.default.fileExists(atPath: next.folder.appending(path: "Take 01/01 Bass.wav").path))
        #expect(FileManager.default.fileExists(atPath: next.folder.appending(path: "Take 01/02 USB 02.wav").path))
    }
}

import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
@testable import TakeFile
import Testing

private extension StemWriter {
    func append(_ samples: [Float]) throws { try samples.withUnsafeBufferPointer { try append($0) } }
}

/// A Take cut off by a crash or a kill is finished at the next launch (#319).
@MainActor
@Suite("Cut-off Take")
struct CutOffTakeTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "CutOffTakeTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let show = "2026-10-06 Show"

    func recorder() -> Recorder {
        let drive = drive
        return Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
    }

    func stems(_ parent: URL) -> [URL] {
        let take = parent.appending(path: "\(show)/Take 01")
        return ((try? FileManager.default.contentsOfDirectory(at: take, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "wav" }.sorted { $0.path < $1.path }
    }

    /// Appends `frames` whole 24-bit samples, plus `stray` bytes of a torn sample, without touching the header:
    /// what a crash between header commits leaves.
    func append(_ frames: Int, stray: Int, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0x10, count: frames * 3 + stray))
        try handle.close()
    }

    /// A finished 480-frame Take on both Copies, then cut off: the Device has 100 more frames on disk than its
    /// headers say, the Drive 40, and the Show doesn't know the Take ended.
    func cutOffTake() async throws {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let first = recorder()
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try first.arm(audio)
        try first.startTake()
        audio.deliver([Array(repeating: 0.2, count: 480), Array(repeating: 0.2, count: 480)])
        try await first.stopTake()
        await first.waitForRepair()
        first.disarm()
        for stem in stems(device) { try append(100, stray: 2, to: stem) }
        for stem in stems(drive) { try append(40, stray: 0, to: stem) }
        for parent in [device, drive] {
            let folder = parent.appending(path: show)
            var file = try #require(ShowFile.read(from: folder))
            file.lastTakeEndedAt = nil
            try file.write(to: folder)
            try? FileManager.default.removeItem(at: folder.appending(path: "Report.html"))
            try? FileManager.default.removeItem(at: folder.appending(path: "\(show).RPP"))
        }
    }

    @Test("At launch the cut-off Take's Stems cover the audio on disk, the shorter Copy is Repaired, and the report and project are written again")
    func finishesAtLaunch() async throws {
        try await cutOffTake()
        let next = recorder()
        await next.waitForRepair()

        for stem in stems(device) {
            #expect(try StemFile.inspect(stem).frameCount == 580)
            let region = try #require((try? StemFile.inspect(stem))?.audioRegion)
            let size = try #require(try FileManager.default.attributesOfItem(atPath: stem.path)[.size] as? UInt64)
            #expect(size == region.offset + 580 * 3, "the torn sample is cut off")
        }
        let metadata = try JSONDecoder.takeMetadata.decode(TakeMetadata.self, from: Data(contentsOf: device.appending(path: "\(show)/Take 01/Take.json")))
        #expect(metadata.gaps.contains(TakeMetadata.Gap(copy: .drive, start: 520, end: 580)))
        for stem in stems(drive) {
            #expect(try StemFile.inspect(stem).frameCount == 580, "Repair filled the Drive Copy from the Device")
        }
        for parent in [device, drive] {
            #expect(FileManager.default.fileExists(atPath: parent.appending(path: "\(show)/Report.html").path))
            #expect(FileManager.default.fileExists(atPath: parent.appending(path: "\(show)/\(show).RPP").path))
        }
    }

    @Test("A cut-off Take whose Device Take.json is missing is still finished in both Copies, from the Drive's (#626)")
    func deviceTakeFileMissing() async throws {
        try await cutOffTake()
        try FileManager.default.removeItem(at: device.appending(path: "\(show)/Take 01/Take.json"))
        let next = recorder()
        try await waitUntil { !next.isRepairing }
        await next.waitForRepair()

        for stem in stems(device) { #expect(try StemFile.inspect(stem).frameCount == 580) }
        let metadata = try JSONDecoder.takeMetadata.decode(TakeMetadata.self, from: Data(contentsOf: device.appending(path: "\(show)/Take 01/Take.json")))
        #expect(metadata.gaps.contains(TakeMetadata.Gap(copy: .drive, start: 520, end: 580)))
        for stem in stems(drive) { #expect(try StemFile.inspect(stem).frameCount == 580, "Repair filled the Drive Copy from the Device") }
    }

    @Test("A launch over a cut-off Take only finishes it: nothing is Armed or recording, and no new Take is started")
    func launchStartsNothing() async throws {
        try await cutOffTake()
        let next = recorder()
        await next.waitForRepair()

        #expect(!next.isArmed)
        #expect(!next.isRecording)
        for parent in [device, drive] {
            #expect(!FileManager.default.fileExists(atPath: parent.appending(path: "\(show)/Take 02").path))
        }
    }

    /// Drive only, cut off while a stand-in was recording: the Drive's Take.json doesn't list the stand-in and the
    /// Device never got its own, so only the `Stand-in <start>` folder says there was one (#632).
    func driveOnlyTakeWithStandIn(standInFrames: Int, committed: Int) throws -> (show: Show, folders: [DestinationKind: URL]) {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        var show = try Show.create(in: device, drive: drive, on: RecordingTakeTests.showDay)
        let folders = try show.createNextTakeFolder()
        let metadata = TakeMetadata(
            show: show.name, take: 1, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        try metadata.write(to: folders[.drive]!)
        let info = StemWriter.Info(
            sampleRate: 48_000, description: "", originator: "ShowRecorder", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        // The Drive's Stem: whole, 300 frames, then it was pulled.
        let driveStem = try StemWriter.open(url: folders[.drive]!.appending(path: "01 USB 01.wav"), info: info, resumingAt: nil)
        try driveStem.append(Array(repeating: 0.1, count: 300))
        try driveStem.finalize()
        // The stand-in's Stem starts at frame 300: `committed` frames made it into the header, the rest only to disk.
        let standIn = folders[.device]!.appending(path: TakeMetadata.StandIn(start: 300, end: 300).folderName)
        try FileManager.default.createDirectory(at: standIn, withIntermediateDirectories: true)
        let stem = try StemWriter.open(url: standIn.appending(path: "01 USB 01.wav"), info: info, resumingAt: nil)
        try stem.append(Array(repeating: 0.1, count: committed))
        try stem.commitHeader()
        try stem.append(Array(repeating: 0.1, count: standInFrames - committed))
        return (show, folders)
    }

    @Test("Drive only: a stand-in cut off before the Device's Take.json was written is found by its folder and finished (#632)")
    func standInWithoutDeviceTakeFile() throws {
        let (show, folders) = try driveOnlyTakeWithStandIn(standInFrames: 200, committed: 100)

        let found = try #require(CutOffTake.finish(deviceShow: show.folder, driveShow: show.driveFolder, lastTakeEndedAt: nil))

        #expect(found.metadata.standIns == [.init(start: 300, end: 500)])
        #expect(found.metadata.gaps == [TakeMetadata.Gap(copy: .drive, start: 300, end: 500)])
        #expect(found.folders[.device] == folders[.device])
        let stem = folders[.device]!.appending(path: "Stand-in 300/01 USB 01.wav")
        #expect(try StemFile.inspect(stem).frameCount == 200, "its header covers what reached the disk")
        // Both Take.json files now say so, so a launch after this one finds the same Take.
        for kind in [DestinationKind.device, .drive] {
            let written = try TakeMetadata.read(fromTakeFolder: folders[kind]!)
            #expect(written.standIns == [.init(start: 300, end: 500)])
        }
    }

    @Test("Only folders named as a stand-in names its own are taken as stand-ins; a stray one never stops a launch (#632)")
    func strayStandInFolderNames() throws {
        let (show, folders) = try driveOnlyTakeWithStandIn(standInFrames: 200, committed: 100)
        for name in ["Stand-in -1", "Stand-in +300", "Stand-in 0300", "Stand-in 300 copy"] {
            try FileManager.default.createDirectory(at: folders[.device]!.appending(path: name), withIntermediateDirectories: true)
        }

        let found = try #require(CutOffTake.finish(deviceShow: show.folder, driveShow: show.driveFolder, lastTakeEndedAt: nil))

        #expect(found.metadata.standIns == [.init(start: 300, end: 500)])
    }

    @Test("Finishing is done once: a second launch changes no file")
    func idempotent() async throws {
        try await cutOffTake()
        let once = recorder()
        await once.waitForRepair()
        let before = try stems(device).map { try Data(contentsOf: $0) } + stems(drive).map { try Data(contentsOf: $0) }
        let take = try Data(contentsOf: device.appending(path: "\(show)/Take 01/Take.json"))

        let twice = recorder()
        await twice.waitForRepair()
        #expect(try stems(device).map { try Data(contentsOf: $0) } + stems(drive).map { try Data(contentsOf: $0) } == before)
        #expect(try Data(contentsOf: device.appending(path: "\(show)/Take 01/Take.json")) == take)
    }
}

extension JSONDecoder {
    static var takeMetadata: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

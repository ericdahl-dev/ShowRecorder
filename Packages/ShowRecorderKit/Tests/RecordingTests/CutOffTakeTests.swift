import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
@testable import TakeFile
import Testing

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
        try first.stopTake()
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
            #expect(try StemLength.frameCount(at: stem) == 580)
            let region = try #require(StemLength.audioRegion(at: stem))
            let size = try #require(try FileManager.default.attributesOfItem(atPath: stem.path)[.size] as? UInt64)
            #expect(size == region.offset + 580 * 3, "the torn sample is cut off")
        }
        let metadata = try JSONDecoder.takeMetadata.decode(TakeMetadata.self, from: Data(contentsOf: device.appending(path: "\(show)/Take 01/Take.json")))
        #expect(metadata.gaps.contains(TakeMetadata.Gap(copy: .drive, start: 520, end: 580)))
        for stem in stems(drive) {
            #expect(try StemLength.frameCount(at: stem) == 580, "Repair filled the Drive Copy from the Device")
        }
        for parent in [device, drive] {
            #expect(FileManager.default.fileExists(atPath: parent.appending(path: "\(show)/Report.html").path))
            #expect(FileManager.default.fileExists(atPath: parent.appending(path: "\(show)/\(show).RPP").path))
        }
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

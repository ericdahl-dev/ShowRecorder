import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#656): a Take that can't move whole stays on the iPhone. The operator may delete it by hand once the Drive
/// verifiably holds everything the Device holds of it: `CopyCheck.verifyHeld` compares only those frames, sample for sample.
@Suite("The Drive holds what the Device holds")
struct CopyCheckHeldTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "CopyCheckHeldTests-\(UUID().uuidString)")
    var deviceTake: URL { root.appending(path: "Device/2026-10-06 Show/Take 01") }
    var driveTake: URL { root.appending(path: "Drive/2026-10-06 Show/Take 01") }
    static let startedAt = Date(timeIntervalSince1970: 1_791_331_200)

    static func channel(_ number: Int) -> TakeMetadata.USBChannel {
        .init(usbChannel: number, stemFile: String(format: "%02d USB %02d.wav", number, number), source: .fallback(usbChannel: number))
    }

    func metadata(channels: Int = 1) -> TakeMetadata {
        var metadata = TakeMetadata(
            show: "2026-10-06 Show", take: 1, startedAt: Self.startedAt, sampleRate: 48_000, timeReference: 0,
            usbChannels: (1...channels).map(Self.channel))
        metadata.driveOnly = true
        return metadata
    }

    /// A Stem of `frames` counting samples of `channel`, silent over `silent`, and 0.5 over `differs`.
    func writeStem(_ url: URL, frames: Int, channel: Int = 1, silent: Range<Int>? = nil, differs: Range<Int>? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "Test", timeReference: 0, originationDate: Self.startedAt)
        let stem = try StemWriter(url: url, info: info)
        let samples = (0..<frames).map { frame -> Float in
            if silent?.contains(frame) == true { return 0 }
            if differs?.contains(frame) == true { return 0.5 }
            return counting()(frame, channel - 1)
        }
        try samples.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    func writeTakes(_ metadata: TakeMetadata, driveGaps: [TakeMetadata.Gap] = []) throws {
        for folder in [deviceTake, driveTake] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try metadata.write(to: deviceTake)
        var onDrive = metadata
        onDrive.standIns = nil
        onDrive.gaps = driveGaps
        try onDrive.write(to: driveTake)
    }

    func stem(_ folder: URL, _ channel: Int = 1) -> URL { folder.appending(path: Self.channel(channel).stemFile) }

    func reasons(_ result: CopyCheck.Result) -> [String] {
        if case .failed(let reasons) = result { return reasons }
        return []
    }

    @Test("Channels of different lengths on the Device pass when the Drive has each one's frames, and more is fine")
    func channelsOfDifferentLengths() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = metadata(channels: 2)
        try writeTakes(metadata)
        try writeStem(stem(deviceTake, 1), frames: 4_800, channel: 1)
        try writeStem(stem(deviceTake, 2), frames: 3_000, channel: 2)
        try writeStem(stem(driveTake, 1), frames: 4_800, channel: 1)
        try writeStem(stem(driveTake, 2), frames: 4_800, channel: 2)   // the Drive's is longer

        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake) == .passed)
    }

    @Test("A sample that differs anywhere in what the Device holds fails, and says which channel")
    func differingSample() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = metadata(channels: 2)
        try writeTakes(metadata)
        for channel in 1...2 { try writeStem(stem(deviceTake, channel), frames: 4_800, channel: channel) }
        try writeStem(stem(driveTake, 1), frames: 4_800, channel: 1)
        try writeStem(stem(driveTake, 2), frames: 4_800, channel: 2, differs: 4_000..<4_001)

        let problems = reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake))
        #expect(problems.count == 1)
        #expect(problems.first?.contains("channel 2") == true)
    }

    @Test("A Drive Stem shorter than the Device's fails")
    func shorterOnTheDrive() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTakes(metadata())
        try writeStem(stem(deviceTake), frames: 4_800)
        try writeStem(stem(driveTake), frames: 1_000)

        #expect(reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).first?.contains("channel 1") == true)
    }

    @Test("Frames inside the Device's own Gaps are not compared: it holds no audio there, the Drive may")
    func deviceGapsAreNotCompared() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = metadata()
        metadata.gaps = [.init(copy: .device, start: 2_000, end: 2_100)]
        try writeTakes(metadata)
        try writeStem(stem(deviceTake), frames: 4_800, silent: 2_000..<2_100)
        try writeStem(stem(driveTake), frames: 4_800)   // real audio where the Device has silence

        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake) == .passed)
    }

    @Test("A stand-in is compared where it sits in the Take, and the rest of the Drive Stem is not")
    func standInHeld() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = metadata()
        metadata.standIns = [.init(start: 3_000, end: 5_000)]
        try writeTakes(metadata)
        // The stand-in holds Take frames 3,000 to 5,000.
        let standIn = deviceTake.appending(path: metadata.standIns![0].folderName)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 3_000, originationDate: Self.startedAt)
        try FileManager.default.createDirectory(at: standIn, withIntermediateDirectories: true)
        let held = try StemWriter(url: stem(standIn), info: info)
        try (3_000..<5_000).map { counting()($0, 0) }.withUnsafeBufferPointer { try held.append($0) }
        try held.finalize()
        // The Drive has those frames, but silence from 5,000 on (what the stand-in never covered).
        try writeStem(stem(driveTake), frames: 8_000, silent: 5_000..<8_000)

        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake) == .passed)

        try writeStem(stem(driveTake), frames: 8_000, differs: 4_000..<4_010)
        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty, "a differing sample inside the stand-in fails")
    }

    @Test("A stand-in Stem that can't be read fails")
    func unreadableStandIn() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = metadata()
        metadata.standIns = [.init(start: 0, end: 1_000)]
        try writeTakes(metadata)
        try writeStem(stem(driveTake), frames: 1_000)

        #expect(reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).first?.contains("channel 1") == true)
    }

    @Test("Two different recordings are never compared")
    func anotherRecording() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTakes(metadata())
        var other = metadata()
        other.startedAt = Self.startedAt.addingTimeInterval(60)
        try other.write(to: driveTake)
        try writeStem(stem(deviceTake), frames: 1_000)
        try writeStem(stem(driveTake), frames: 1_000)

        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty)
    }

    @Test("A check asked to stop is neither passed nor failed")
    func stopped() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTakes(metadata())
        try writeStem(stem(deviceTake), frames: 4_800)
        try writeStem(stem(driveTake), frames: 4_800)

        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake, shouldStop: { true }) == nil)
    }

    // MARK: - What a delete gate must not let through

    /// A Stand-in folder holding one Stem of Take frames `range`.
    func writeStandIn(_ standIn: TakeMetadata.StandIn, frames: Range<Int>? = nil, differs: Range<Int>? = nil) throws {
        let range = frames ?? standIn.start..<standIn.end
        let folder = deviceTake.appending(path: standIn.folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: UInt64(standIn.start), originationDate: Self.startedAt)
        let stem = try StemWriter(url: stem(folder), info: info)
        try range.map { differs?.contains($0) == true ? Float(0.5) : counting()($0, 0) }.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    @Test("A Device holding root Stems and degenerate stand-ins is still compared on its Stems")
    func rootStemsAreNotSkippedBecauseOfStandIns() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = metadata()
        metadata.standIns = [.init(start: 2_000, end: 2_000)]
        try writeTakes(metadata)
        try FileManager.default.createDirectory(at: deviceTake.appending(path: metadata.standIns![0].folderName), withIntermediateDirectories: true)
        try writeStem(stem(deviceTake), frames: 4_800)
        try writeStem(stem(driveTake), frames: 4_800, differs: 3_000..<3_001)

        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty, "the root Stem differs from the Drive's")
    }

    @Test("A stand-in that lists no range but holds audio fails")
    func degenerateStandInWithAudio() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = metadata()
        metadata.standIns = [.init(start: 1_000, end: 1_000)]
        try writeTakes(metadata)
        try writeStandIn(.init(start: 1_000, end: 1_000), frames: 1_000..<1_100)
        try writeStem(stem(driveTake), frames: 4_800, silent: 1_000..<1_100)

        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty)
    }

    @Test("A Device Take folder holding an audio file or a stand-in folder the Take.json doesn't list fails")
    func unlistedFiles() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTakes(metadata())
        try writeStem(stem(deviceTake), frames: 1_000)
        try writeStem(stem(driveTake), frames: 1_000)
        try writeStem(deviceTake.appending(path: "02 USB 02.wav"), frames: 500, channel: 2)
        #expect(reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).first?.contains("doesn't list") == true)

        try FileManager.default.removeItem(at: deviceTake.appending(path: "02 USB 02.wav"))
        try writeStandIn(.init(start: 0, end: 500))   // a stand-in folder, with no `standIns` entry for it
        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty)
    }

    @Test("A Device Gap over audio the Drive lacks is no excuse: only silence, or the Drive's own bytes, passes")
    func staleGapDoesNotHideAudio() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = metadata()
        metadata.gaps = [.init(copy: .device, start: 1_000, end: 3_000)]   // bigger than the silence the Device really has
        try writeTakes(metadata)
        try writeStem(stem(deviceTake), frames: 4_800, silent: 1_000..<1_100)
        try writeStem(stem(driveTake), frames: 4_800, silent: 1_000..<3_000)   // the Drive lacks 1,100..<3,000 that the Device has

        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty)
    }

    @Test("A Gap that no longer hides anything is harmless: where the Drive holds the same bytes it passes")
    func staleGapWithTheSameAudio() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = metadata()
        metadata.gaps = [.init(copy: .device, start: 1_000, end: 3_000)]
        try writeTakes(metadata)
        try writeStem(stem(deviceTake), frames: 4_800)
        try writeStem(stem(driveTake), frames: 4_800)

        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake) == .passed)
    }

    @Test("A Take.json with a Gap or a stand-in that can't be fails, and doesn't trap")
    func impossibleNumbers() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var gapped = metadata()
        gapped.gaps = [.init(copy: .device, start: 3_000, end: 2_000)]
        try writeTakes(gapped)
        try writeStem(stem(deviceTake), frames: 1_000)
        try writeStem(stem(driveTake), frames: 1_000)
        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty)

        var negative = metadata()
        negative.standIns = [.init(start: -5, end: 100)]
        try negative.write(to: deviceTake)
        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty)
    }

    @Test("A Device channel the Drive's Take.json doesn't have, or an unreadable Device Stem, fails")
    func missingAndUnreadable() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = metadata(channels: 2)
        try writeTakes(metadata)
        var short = metadata
        short.usbChannels = [Self.channel(1)]
        try short.write(to: driveTake)
        for channel in 1...2 { try writeStem(stem(deviceTake, channel), frames: 500, channel: channel) }
        try writeStem(stem(driveTake, 1), frames: 500)
        #expect(reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).first?.contains("channel 2 is missing") == true)

        try metadata.write(to: driveTake)
        try writeStem(stem(driveTake, 2), frames: 500, channel: 2)
        try Data("not a wave file".utf8).write(to: stem(deviceTake, 2))
        #expect(reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).first?.contains("channel 2 can't be read on the Device") == true)
    }

    @Test("A Device Stem with no frames holds nothing to lose: it passes")
    func emptyDeviceStem() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTakes(metadata())
        try writeStem(stem(deviceTake), frames: 0)
        try writeStem(stem(driveTake), frames: 100)

        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake) == .passed)
    }

    @Test("Long Stems are compared past the first chunk, and a stop between chunks is honored")
    func longStems() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTakes(metadata())
        try writeStem(stem(deviceTake), frames: 600_000)
        try writeStem(stem(driveTake), frames: 600_000, differs: 500_000..<500_001)
        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty, "a difference in the third chunk")

        try writeStem(stem(driveTake), frames: 600_000)
        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake) == .passed)
        nonisolated(unsafe) var asked = 0
        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake, shouldStop: { asked += 1; return asked > 1 }) == nil, "stopped mid-Stem")
    }

    @Test("A stand-in is compared to its last frame and not past it; several stand-ins each at their own place")
    func standInBoundaries() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var metadata = metadata()
        metadata.standIns = [.init(start: 1_000, end: 2_000), .init(start: 5_000, end: 5_500)]
        try writeTakes(metadata)
        try writeStandIn(metadata.standIns![0])
        try writeStandIn(metadata.standIns![1])
        // The Drive differs in the frame just before and just after each range, and nowhere inside.
        try writeStem(stem(driveTake), frames: 8_000, differs: 999..<1_000)
        try writeStem(stem(driveTake), frames: 8_000, differs: 2_000..<2_001)
        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake) == .passed, "outside the ranges is not the Device's to compare")

        try writeStem(stem(driveTake), frames: 8_000, differs: 1_999..<2_000)
        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty, "the last frame of the first range")
        try writeStem(stem(driveTake), frames: 8_000, differs: 5_499..<5_500)
        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty, "the last frame of the second range")
    }

    @Test("An unfinalized Device Stem is compared on the samples that reached the disk")
    func unfinalizedDeviceStem() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTakes(metadata())
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: Self.startedAt)
        let stem = try StemWriter(url: stem(deviceTake), info: info)
        try (0..<1_000).map { counting()($0, 0) }.withUnsafeBufferPointer { try stem.append($0) }   // never committed or finalized
        try writeStem(self.stem(driveTake), frames: 1_000)
        #expect(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake) == .passed)

        try writeStem(self.stem(driveTake), frames: 1_000, differs: 900..<901)
        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty)
    }

    @Test("A Drive Stem whose header declares fewer frames than it holds does not count as holding them")
    func unfinalizedDriveStem() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTakes(metadata())
        try writeStem(stem(deviceTake), frames: 1_000)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: Self.startedAt)
        let stem = try StemWriter(url: stem(driveTake), info: info)
        try (0..<1_000).map { counting()($0, 0) }.withUnsafeBufferPointer { try stem.append($0) }   // header says 0

        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty)
    }

    @Test("A Drive Take.json naming a Stem outside its folder fails")
    func stemNameEscapes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTakes(metadata())
        try writeStem(stem(deviceTake), frames: 500)
        var onDrive = metadata()
        onDrive.usbChannels = [.init(usbChannel: 1, stemFile: "../../../Device/2026-10-06 Show/Take 01/01 USB 01.wav", source: .fallback(usbChannel: 1))]
        try onDrive.write(to: driveTake)

        #expect(!reasons(CopyCheck.verifyHeld(device: deviceTake, drive: driveTake)).isEmpty, "a Device file compared with itself would always match")
    }
}

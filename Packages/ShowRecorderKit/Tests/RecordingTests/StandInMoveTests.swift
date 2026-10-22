import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Drive only (#630): moving one kept stand-in into its Drive Take, from Take folders made by hand.
@Suite("Moving a kept stand-in")
struct StandInMoveTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "StandInMoveTests-\(UUID().uuidString)")
    var deviceShow: URL { root.appending(path: "Device/2026-10-06 Show") }
    var deviceTake: URL { deviceShow.appending(path: "Take 01") }
    var driveTake: URL { root.appending(path: "Drive/2026-10-06 Show/Take 01") }
    static let startedAt = Date(timeIntervalSince1970: 1_791_331_200)

    static func channel(_ number: Int, _ file: String? = nil, name: String? = nil) -> TakeMetadata.USBChannel {
        .init(
            usbChannel: number, stemFile: file ?? String(format: "%02d USB %02d.wav", number, number), name: name ?? String(format: "USB %02d", number),
            hasMixerName: false, color: .init(hue: "off", inverted: false))
    }

    static func metadata(_ channels: [TakeMetadata.USBChannel], standIn: TakeMetadata.StandIn, gaps: [TakeMetadata.Gap]) -> TakeMetadata {
        var metadata = TakeMetadata(show: "2026-10-06 Show", take: 1, startedAt: startedAt, sampleRate: 48_000, timeReference: 0, usbChannels: channels)
        metadata.gaps = gaps
        metadata.standIns = [standIn]
        metadata.driveOnly = true
        return metadata
    }

    /// A Stem holding `frames`, frame `f` of channel `channel` being `counting()(f, channel)`, silent over `silent`.
    func writeStem(_ url: URL, frames: Range<Int>, channel: Int, silent: Range<Int>? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "Test", timeReference: 0, originationDate: Self.startedAt)
        let stem = try StemWriter(url: url, info: info)
        let samples = frames.map { silent?.contains($0) == true ? 0 : counting()($0, channel - 1) }
        try samples.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    /// A kept stand-in over `standIn` on the Device, its Stems `standInFrames` long (all of it by default), and its
    /// Drive Take with `driveFrames`, silent over the Drive Gap, which isn't repaired yet.
    @discardableResult
    func make(
        channels: Int = 1, standIn: TakeMetadata.StandIn = .init(start: 0, end: 7_200), gap: Range<Int> = 2_400..<7_200,
        driveFrames: Int = 7_200, standInFrames: [Int]? = nil
    ) throws -> (device: TakeMetadata, drive: TakeMetadata) {
        let list = (1...channels).map { Self.channel($0) }
        let metadata = Self.metadata(list, standIn: standIn, gaps: [.init(copy: .drive, start: gap.lowerBound, end: gap.upperBound)])
        for folder in [deviceTake, driveTake] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try metadata.write(to: deviceTake)
        try metadata.write(to: driveTake)
        for (index, channel) in list.enumerated() {
            let frames = standInFrames?[index] ?? (standIn.end - standIn.start)
            try writeStem(
                deviceTake.appending(path: standIn.folderName).appending(path: channel.stemFile),
                frames: standIn.start..<(standIn.start + frames), channel: channel.usbChannel)
            try writeStem(driveTake.appending(path: channel.stemFile), frames: 0..<driveFrames, channel: channel.usbChannel, silent: gap)
        }
        return (metadata, metadata)
    }

    func driveStem(_ channel: Int = 1) -> URL { driveTake.appending(path: Self.channel(channel).stemFile) }

    func samples(_ url: URL, _ frames: Range<Int>) throws -> [Float] { try StemWriter.readSamples(url: url, frames: frames) }

    func expected(_ frames: Range<Int>, channel: Int = 1) -> [Float] { frames.map { counting()($0, channel - 1) } }

    func run(shouldStop: @escaping () -> Bool = { false }, at hook: @escaping (StandInMove.Step) -> Void = { _ in }) -> StandInMove.Outcome {
        StandInMove.run(deviceTake: deviceTake, driveTake: driveTake, shouldStop: shouldStop, at: hook)
    }

    func reasons(_ outcome: StandInMove.Outcome) -> [String] {
        if case .kept(let reasons) = outcome { return reasons }
        Issue.record("not kept: \(outcome)")
        return []
    }

    @Test("A stand-in whose start isn't the Take's start fills the Drive at its own frames")
    func standInAfterTheStart() throws {
        try make(standIn: .init(start: 2_400, end: 7_200))

        #expect(run() == .moved)
        #expect(try samples(driveStem(), 0..<7_200) == expected(0..<7_200))
        #expect(!FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A Drive Take of another recording is never written: its audio stays byte for byte")
    func anotherRecordingOnTheDrive() throws {
        try make()
        var other = try TakeMetadata.read(fromTakeFolder: driveTake)
        other.startedAt = Self.startedAt.addingTimeInterval(60)
        try other.write(to: driveTake)
        let before = try Data(contentsOf: driveStem())

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("another recording") }, "\(reasons)")
        #expect(try Data(contentsOf: driveStem()) == before)
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A channel renamed on the Device only still moves, and the Drive keeps its own names and Markers")
    func renamedOnTheDeviceOnly() throws {
        try make()
        var drive = try TakeMetadata.read(fromTakeFolder: driveTake)
        drive.markers = [.init(position: 100, name: "Marker 1", origin: .operator)]
        try drive.write(to: driveTake)
        var device = try TakeMetadata.read(fromTakeFolder: deviceTake)
        device.usbChannels = [Self.channel(1, "01 Kick.wav", name: "Kick")]
        device.markers = [.init(position: 100, name: "Intro", origin: .operator)]
        try device.write(to: deviceTake)
        let standIn = deviceTake.appending(path: "Stand-in 0")
        try FileManager.default.moveItem(at: standIn.appending(path: "01 USB 01.wav"), to: standIn.appending(path: "01 Kick.wav"))

        #expect(run() == .moved)
        let after = try TakeMetadata.read(fromTakeFolder: driveTake)
        #expect(after.usbChannels == drive.usbChannels)
        #expect(after.markers.map(\.name) == ["Marker 1"])
        #expect(try samples(driveStem(), 0..<7_200) == expected(0..<7_200))
    }

    @Test("When the Drive's Take.json can't be written after setting aside, the Device's Take is put back and kept")
    func clearingStandInsFails() throws {
        try make()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: driveTake.path) }

        let outcome = run(at: { step in
            if step == .setAside { try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: driveTake.path) }
        })

        #expect(!reasons(outcome).isEmpty)
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path), "the Device's Take is back")
        #expect(!FileManager.default.fileExists(atPath: deviceShow.appending(path: ".moved Take 01").path))
    }

    @Test("Stand-in Stems of unequal length (a cut-off crash) are no false Repair: the Device keeps the Take, with why")
    func unequalStandInStems() throws {
        try make(channels: 2, standInFrames: [7_200, 6_000])

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("channel 2") }, "\(reasons)")
        #expect(try !TakeMetadata.read(fromTakeFolder: driveTake).repairs.contains { $0.outcome == .repaired })
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Stand-in 0/02 USB 02.wav").path))
    }

    @Test("A Device Take holding anything but its Take.json and stand-ins is kept, with why")
    func strayFileOnTheDevice() throws {
        try make()
        try Data("notes".utf8).write(to: deviceTake.appending(path: "notes.txt"))

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("notes.txt") || $0.contains("other files") }, "\(reasons)")
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "notes.txt").path))
    }

    @Test("A Device Take already gone is nothing to do")
    func goneFromTheDevice() throws {
        #expect(run() == .gone)
    }

    @Test("A Take started between Stems stops the move with the first filled, and a later move finishes it")
    func stopBetweenStems() throws {
        try make(channels: 2)
        var asked = 0

        // Asked before the first Stem and once within it, then before the second.
        #expect(run(shouldStop: { asked += 1; return asked > 2 }) == .stopped)
        #expect(try samples(driveStem(1), 0..<7_200) == expected(0..<7_200), "the first Stem is filled")
        #expect(try samples(driveStem(2), 2_400..<7_200) == Array(repeating: 0, count: 4_800), "the second isn't yet")
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))

        #expect(run() == .moved)
        #expect(try samples(driveStem(2), 0..<7_200) == expected(0..<7_200, channel: 2))
    }

    @Test("A second check that fails puts the Device's Take back and the stand-in back in the Drive's Take.json")
    func secondCheckFails() throws {
        try make()

        let outcome = run(at: { step in
            // The Drive changes after the Take is set aside.
            if step == .setAside { try? self.writeStem(self.driveStem(), frames: 0..<7_200, channel: 1, silent: 0..<100) }
        })

        #expect(!reasons(outcome).isEmpty)
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Stand-in 0/01 USB 01.wav").path))
        #expect(!FileManager.default.fileExists(atPath: deviceShow.appending(path: ".moved Take 01").path))
        #expect(try TakeMetadata.read(fromTakeFolder: driveTake).standIns == [.init(start: 0, end: 7_200)])
    }

    @Test("Drive audio outside the unrepaired Gap that differs from the stand-in is left as it is, and the stand-in kept")
    func driveAudioOutsideTheGap() throws {
        try make(gap: 2_400..<4_800)
        // The stand-in lost frames the Drive has, outside the Gap.
        try writeStem(deviceTake.appending(path: "Stand-in 0/01 USB 01.wav"), frames: 0..<7_200, channel: 1, silent: 5_000..<5_100)
        let outside = try samples(driveStem(), 4_800..<7_200)

        #expect(!reasons(run()).isEmpty)
        #expect(try samples(driveStem(), 4_800..<7_200) == outside)
        #expect(try samples(driveStem(), 0..<2_400) == expected(0..<2_400))
        #expect(FileManager.default.fileExists(atPath: deviceTake.path))
    }

    @Test("A Drive Stem shorter than where the stand-in starts is kept, with nothing written")
    func driveShorterThanTheStandIn() throws {
        try make(standIn: .init(start: 2_400, end: 7_200), gap: 7_200..<7_200, driveFrames: 1_000)
        let before = try Data(contentsOf: driveStem())

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("before its stand-in") }, "\(reasons)")
        #expect(try Data(contentsOf: driveStem()) == before)
    }

    @Test("A set-aside folder left by an earlier move keeps the Take, and says so")
    func leftoverSetAside() throws {
        try make()
        try FileManager.default.createDirectory(at: deviceShow.appending(path: ".moved Take 01"), withIntermediateDirectories: true)

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains(".moved Take 01") }, "\(reasons)")
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path))
    }

    @Test("A set-aside folder that can't be removed is reported, not taken for a move")
    func setAsideNotRemoved() throws {
        try make()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deviceShow.path) }

        let outcome = run(at: { step in
            if step == .removing { try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: deviceShow.path) }
        })

        #expect(reasons(outcome).contains { $0.contains("couldn't be removed") }, "\(outcome)")
        #expect(try samples(driveStem(), 0..<7_200) == expected(0..<7_200), "the Drive has it all")
    }

    /// Leaves the Drive's Take.json with no Gaps: the Gap is known only to the Device's.
    func forgetGapsOnTheDrive() throws {
        var drive = try TakeMetadata.read(fromTakeFolder: driveTake)
        drive.gaps = []
        try drive.write(to: driveTake)
    }

    @Test("A Gap only the Device's Take.json knows is filled, and the Drive's Take.json then lists it, Repaired")
    func gapKnownOnlyToTheDevice() throws {
        try make()
        try forgetGapsOnTheDrive()

        #expect(run() == .moved)
        #expect(try samples(driveStem(), 0..<7_200) == expected(0..<7_200))
        let after = try TakeMetadata.read(fromTakeFolder: driveTake)
        #expect(after.gaps == [.init(copy: .drive, start: 2_400, end: 7_200)])
        #expect(after.repairs == [.init(copy: .drive, start: 2_400, end: 7_200, outcome: .repaired)])
    }

    @Test("A Gap only the Device's Take.json knows that the stand-in doesn't hold keeps the Take, with a failed Repair")
    func gapKnownOnlyToTheDeviceNotHeld() throws {
        try make(standIn: .init(start: 2_400, end: 7_200), gap: 0..<3_000)
        try forgetGapsOnTheDrive()

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("doesn't hold") }, "\(reasons)")
        #expect(try TakeMetadata.read(fromTakeFolder: driveTake).repairs == [
            .init(copy: .drive, start: 0, end: 2_400, outcome: .failed), .init(copy: .drive, start: 2_400, end: 3_000, outcome: .repaired),
        ])
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path))
    }

    @Test("A Drive Gap that starts before the stand-in is split at its start: the part it holds is repaired, the rest failed (#916)")
    func gapStartingBeforeTheStandIn() throws {
        try make(standIn: .init(start: 2_400, end: 7_200), gap: 0..<7_200)

        let reasons = reasons(run())

        #expect(reasons.contains { $0.contains("doesn't hold") }, "\(reasons)")
        #expect(try samples(driveStem(), 2_400..<7_200) == expected(2_400..<7_200))
        let after = try TakeMetadata.read(fromTakeFolder: driveTake)
        #expect(after.gaps == [.init(copy: .drive, start: 0, end: 2_400), .init(copy: .drive, start: 2_400, end: 7_200)])
        #expect(after.repairs == [.init(copy: .drive, start: 0, end: 2_400, outcome: .failed), .init(copy: .drive, start: 2_400, end: 7_200, outcome: .repaired)])
        #expect(after.standIns == [.init(start: 2_400, end: 7_200)])
        #expect(FileManager.default.fileExists(atPath: deviceTake.appending(path: "Take.json").path))
    }

    @Test("A second move of a stand-in that can't fill the whole Gap writes no Stem again, and records the same (#916)")
    func secondMoveWritesNothing() throws {
        try make(standIn: .init(start: 2_400, end: 7_200), gap: 0..<7_200)
        _ = run()
        let written = try driveStem().resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let record = try TakeMetadata.read(fromTakeFolder: driveTake)

        #expect(reasons(run()).contains { $0.contains("doesn't hold") })
        #expect(try driveStem().resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == written)
        let after = try TakeMetadata.read(fromTakeFolder: driveTake)
        #expect(after.gaps == record.gaps)
        #expect(after.repairs == record.repairs)
    }

    @Test("A Take an earlier version recorded as failed over the whole Gap is split, and the old record goes (#916)")
    func earlierWholeGapFailure() throws {
        try make(standIn: .init(start: 2_400, end: 7_200), gap: 0..<7_200)
        var drive = try TakeMetadata.read(fromTakeFolder: driveTake)
        drive.repairs = [.init(copy: .drive, start: 0, end: 7_200, outcome: .failed)]
        try drive.write(to: driveTake)

        _ = run()

        #expect(try TakeMetadata.read(fromTakeFolder: driveTake).repairs == [
            .init(copy: .drive, start: 0, end: 2_400, outcome: .failed), .init(copy: .drive, start: 2_400, end: 7_200, outcome: .repaired),
        ])
    }

    @Test("After a move splits a Gap its stand-in can't fill, the mover skips the Take instead of nominating it again (#916)")
    func moverSkipsAfterTheSplit() throws {
        try make(standIn: .init(start: 2_400, end: 7_200), gap: 0..<7_200)
        #expect(TakeMover.find(deviceFolder: root.appending(path: "Device"), driveFolder: root.appending(path: "Drive")).map(\.kind) == [.standIn])

        _ = run()

        #expect(TakeMover.find(deviceFolder: root.appending(path: "Device"), driveFolder: root.appending(path: "Drive")).map(\.kind) == [.skipped(.driveHasGaps)])
    }

    @Test("A stand-in Stem holding more on disk than its header says keeps the Take: the tail is on the Device only (#871)")
    func standInTailPastItsHeader() throws {
        try make()
        let stem = deviceTake.appending(path: "Stand-in 0").appending(path: Self.channel(1).stemFile)
        let handle = try FileHandle(forUpdating: stem)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0x11, count: 100 * StemWriter.bytesPerSample))
        try handle.close()

        #expect(!reasons(run()).isEmpty)
        #expect(FileManager.default.fileExists(atPath: stem.path))
    }

    @Test("A staged Take.json a crash left in the Device's Take doesn't keep it (#914)")
    func stagedTakeJsonDoesntKeepTheTake() throws {
        try make()
        try Data().write(to: deviceTake.appending(path: ".Take.json.\(UUID().uuidString)"))

        #expect(run() == .moved)
    }

    @Test("A hidden file that only looks like a staged Take.json still keeps the Take (#914)")
    func lookAlikeKeepsTheTake() throws {
        try make()
        try Data().write(to: deviceTake.appending(path: ".Take.json.tmp"))

        #expect(reasons(run()).contains { $0.contains(".Take.json.tmp") })
    }

    @Test("A .DS_Store the Finder left in the Device's Take or its stand-in doesn't keep the Take")
    func finderFilesDontKeepTheTake() throws {
        try make()
        for folder in [deviceTake, deviceTake.appending(path: "Stand-in 0")] {
            try Data().write(to: folder.appending(path: ".DS_Store"))
        }

        #expect(run() == .moved)
        #expect(!FileManager.default.fileExists(atPath: deviceTake.path))
    }
}

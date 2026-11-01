import AudioIO
import Destinations
import Foundation
import Testing

@testable import BroadcastWave
@testable import Recording

/// Checking that the Drive Copy of a Show is whole before the Device Copy is deleted.
@MainActor
@Suite("Check the Drive copy")
struct CopyCheckTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let show = "2026-10-06 Show"

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "CopyCheckTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// Two Takes of 2 channels in both Copies, the Show ended.
    func record() async throws {
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)
        for _ in 1...2 {
            try recorder.startTake()
            audio.deliver((0..<2).map { c in (0..<4_800).map { Float(($0 + c * 7) % 1000) / 8_388_608 } })
            try await recorder.stopTake()
        }
        recorder.standDown()
        try recorder.endShow()
    }

    func verify() -> CopyCheck.Result { CopyCheck.verify(show: show, device: device, drive: drive) }

    @Test("A Show whose Drive Copy matches the Device Copy passes")
    func cleanShowPasses() async throws {
        try await record()
        #expect(verify() == .passed)
    }

    func failures(_ result: CopyCheck.Result) -> [String] {
        if case .failed(let reasons) = result { return reasons }
        return []
    }

    @Test("A Take missing on the Drive, or the whole Show missing, fails and says which")
    func missingTake() async throws {
        try await record()
        try FileManager.default.removeItem(at: drive.appending(path: "\(show)/Take 02"))
        #expect(failures(verify()) == ["Take 02 is missing on the Drive."])

        try FileManager.default.removeItem(at: drive.appending(path: show))
        #expect(failures(verify()) == ["The Drive doesn't have this Show."])
    }

    @Test("While the Device holds a stand-in the check fails, even with the Drive's Take complete (#627)")
    func standInOnDeviceFails() async throws {
        try await record()
        let takeFolder = device.appending(path: "\(show)/Take 01")
        var take = try TakeMetadata.read(fromTakeFolder: takeFolder)
        let standIn = TakeMetadata.StandIn(start: 0, end: 4_800)
        take.standIns = [standIn]
        try take.write(to: takeFolder)
        let standInFolder = takeFolder.appending(path: standIn.folderName)
        try FileManager.default.createDirectory(at: standInFolder, withIntermediateDirectories: true)
        for channel in take.usbChannels {
            try FileManager.default.moveItem(at: takeFolder.appending(path: channel.stemFile), to: standInFolder.appending(path: channel.stemFile))
        }

        #expect(failures(verify()) == ["Take 01 still has audio only on the Device."])
    }

    @Test("A Drive Copy with Gaps left fails; once Repaired it passes")
    func gaps() async throws {
        try await record()
        let url = drive.appending(path: "\(show)/Take 01/Take.json")
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        var take = try decoder.decode(TakeMetadata.self, from: Data(contentsOf: url))
        take.gaps = [.init(copy: .drive, start: 0, end: 10)]
        try encoder.encode(take).write(to: url)
        #expect(failures(verify()) == ["Take 01 on the Drive still has Gaps."])

        take.repairs = [.init(copy: .drive, start: 0, end: 10, outcome: .repaired)]
        try encoder.encode(take).write(to: url)
        #expect(verify() == .passed)
    }

    @Test("A Stem that is shorter, has different audio, or is missing on the Drive fails")
    func stemDiffers() async throws {
        try await record()
        let stem1 = drive.appending(path: "\(show)/Take 01/01 USB 01.wav")
        let stem2 = drive.appending(path: "\(show)/Take 01/02 USB 02.wav")

        // Same length, one sample changed.
        let handle = try FileHandle(forUpdating: stem1)
        let region = try #require((try? StemFile.inspect(stem1))?.audioRegion)
        try handle.seek(toOffset: region.offset + 6)
        try handle.write(contentsOf: Data([0x7F]))
        try handle.close()
        #expect(failures(verify()) == ["Take 01, channel 1 has different audio on the Drive."])

        // Shorter.
        let cut = try FileHandle(forUpdating: stem2)
        try cut.truncate(atOffset: try #require((try? StemFile.inspect(stem2))?.audioRegion).offset + 300)
        try cut.close()
        #expect(failures(verify()).contains("Take 01, channel 2 is a different length on the Drive."))

        // Gone.
        try FileManager.default.removeItem(at: stem2)
        #expect(failures(verify()).contains("Take 01, channel 2 can't be read on the Drive."))
    }

    func recorderWithDrive(_ connected: Bool = true) -> Recorder {
        let drive = drive
        return Recorder(deviceFolder: device, driveFolder: { connected ? DriveAccess(folder: drive) : nil }, now: { RecordingTakeTests.showDay })
    }

    @Test("Deleting the Device copy after the check removes only the Device copy; a failed check, a missing Drive or an open Show deletes nothing")
    func deleteDeviceCopyAfterCheck() async throws {
        try await record()

        // The Show is ended and the Drive is not connected: nothing is deleted.
        let noDrive = await recorderWithDrive(false).deleteDeviceCopy(of: show)
        #expect(noDrive.deleted.isEmpty && noDrive.failed.first?.reason == "The Drive isn't available.")
        #expect(FileManager.default.fileExists(atPath: device.appending(path: show).path))

        // The Drive Copy differs: refused, with the reasons.
        let stem = drive.appending(path: "\(show)/Take 02/02 USB 02.wav")
        try FileManager.default.removeItem(at: stem)
        let failed = await recorderWithDrive().deleteDeviceCopy(of: show)
        #expect(failed.deleted.isEmpty)
        #expect(failed.failed.first?.reason.contains("channel 2") == true)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: show).path))

        // Put the Drive Copy right: the check passes and only the Device copy goes.
        try FileManager.default.copyItem(at: device.appending(path: "\(show)/Take 02/02 USB 02.wav"), to: stem)
        let ok = await recorderWithDrive().deleteDeviceCopy(of: show)
        #expect(ok.deleted == [.device] && ok.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: device.appending(path: show).path))
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/Take 02/02 USB 02.wav").path))
    }

    @Test("The open Show's Device copy is never deleted, even when the Drive matches")
    func openShowRefused() async throws {
        let recorder = recorderWithDrive()
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([[0.1]])
        try await recorder.stopTake()
        let outcome = await recorder.deleteDeviceCopy(of: show)
        #expect(outcome.deleted.isEmpty)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: show).path))
    }

    // MARK: - One Take, and a stand-in (#630)

    func take(_ copy: URL) -> URL { copy.appending(path: "\(show)/Take 01") }

    /// Changes one sample (frame `frame`) of a Stem.
    func changeSample(_ stem: URL, frame: Int) throws {
        let offset = try StemFile.inspect(stem).audioRegion.offset + UInt64(frame * StemWriter.bytesPerSample)
        let handle = try FileHandle(forUpdating: stem)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let byte = try #require(try handle.read(upToCount: 1)).first! ^ 0x01
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: [byte])
    }

    /// Writes a mono Stem of `samples`.
    func writeStem(_ url: URL, _ samples: [Float], sampleRate: Int = 48_000) throws {
        let info = StemWriter.Info(sampleRate: sampleRate, description: "", originator: "Test", timeReference: 0, originationDate: Date())
        let stem = try StemWriter.open(url: url, info: info, resumingAt: nil)
        try samples.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    /// Gives the Device's Take 01 stand-ins over `ranges`, their Stems holding the Drive's samples over each range,
    /// `short` frames fewer. Returns the stand-ins' folders.
    @discardableResult
    func standIns(_ ranges: [Range<Int>], short: Int = 0) throws -> [URL] {
        try change(take(device)) { $0.standIns = ranges.map { .init(start: $0.lowerBound, end: $0.upperBound) } }
        let metadata = try TakeMetadata.read(fromTakeFolder: take(device))
        return try ranges.map { range in
            let folder = take(device).appending(path: TakeMetadata.StandIn(start: range.lowerBound, end: range.upperBound).folderName)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for channel in metadata.usbChannels {
                let samples = try StemWriter.readSamples(url: take(drive).appending(path: channel.stemFile), frames: range.lowerBound..<(range.upperBound - short))
                try writeStem(folder.appending(path: channel.stemFile), samples, sampleRate: metadata.sampleRate)
            }
            return folder
        }
    }

    func change(_ folder: URL, _ edit: (inout TakeMetadata) -> Void) throws {
        var metadata = try TakeMetadata.read(fromTakeFolder: folder)
        edit(&metadata)
        try metadata.write(to: folder)
    }

    func verifyTake(drive: URL? = nil) -> CopyCheck.Result { CopyCheck.verifyTake(device: take(device), drive: drive ?? take(self.drive)) }
    func verifyStandIn(drive: URL? = nil) -> CopyCheck.Result { CopyCheck.verifyStandIn(deviceTake: take(device), driveTake: drive ?? take(self.drive)) }

    @Test("One Take whose Copies match passes; a one-sample difference or a missing Drive Take fail, with the Show check's words")
    func verifyOneTake() async throws {
        try await record()
        #expect(verifyTake() == .passed)

        try changeSample(take(drive).appending(path: "02 USB 02.wav"), frame: 1_000)
        #expect(verifyTake() == .failed(["Take 01, channel 2 has different audio on the Drive."]))

        try FileManager.default.removeItem(at: take(drive))
        #expect(verifyTake() == .failed(["Take 01 is missing on the Drive."]))
    }

    @Test("A Take is never checked against itself, or through a link")
    func verifyTakeSameOrLinked() async throws {
        try await record()
        #expect(verifyTake(drive: take(device)) == .failed(["Take 01's Device and Drive Copies are the same folder."]))
        #expect(verifyTake(drive: drive.appending(path: "\(show)/../\(show)/Take 01/.")) == .passed, "the same Drive folder spelled differently")

        try FileManager.default.removeItem(at: take(drive))
        try FileManager.default.createSymbolicLink(at: take(drive), withDestinationURL: take(device))
        #expect(verifyTake() == .failed(["Take 01 isn't a folder of its own on the Drive."]))
    }

    @Test("A Take with no channels, from another recording, or at another sample rate never passes")
    func verifyTakeIdentity() async throws {
        try await record()
        try change(take(drive)) { $0.startedAt = $0.startedAt.addingTimeInterval(60) }
        #expect(verifyTake() == .failed(["Take 01 on the Drive is another recording."]))
        try change(take(drive)) { $0.startedAt = $0.startedAt.addingTimeInterval(-60) }
        try change(take(drive)) { $0.sampleRate = 44_100 }
        #expect(verifyTake() == .failed(["Take 01 has a different sample rate on the Drive."]))

        try change(take(device)) { $0.usbChannels = [] }
        try change(take(drive)) { $0.usbChannels = [] }
        #expect(verifyTake() == .failed(["Take 01 has no channels."]))
    }

    @Test("A stand-in whose every Stem equals the Drive's samples over its stretch passes, up to the Drive's last frame")
    func standInMatches() async throws {
        try await record()
        try standIns([1_200..<3_600])
        #expect(verifyStandIn() == .passed)

        try FileManager.default.removeItem(at: take(device).appending(path: "Stand-in 1200"))
        try standIns([1_200..<4_800])
        #expect(verifyStandIn() == .passed, "ends exactly at the Drive's end")
    }

    @Test("A one-sample difference in the stand-in or on the Drive fails")
    func standInDiffers() async throws {
        try await record()
        let folder = try #require(try standIns([1_200..<3_600]).first)
        try changeSample(folder.appending(path: "01 USB 01.wav"), frame: 2_399)
        #expect(verifyStandIn() == .failed(["Take 01, channel 1 of the stand-in at 0:00 has different audio on the Drive."]), "last frame of the stand-in")
        try changeSample(folder.appending(path: "01 USB 01.wav"), frame: 2_399)
        #expect(verifyStandIn() == .passed, "changed back")

        try changeSample(take(drive).appending(path: "02 USB 02.wav"), frame: 1_200)
        #expect(verifyStandIn() == .failed(["Take 01, channel 2 of the stand-in at 0:00 has different audio on the Drive."]), "first frame on the Drive")
    }

    @Test("A stand-in Stem shorter than its stretch, or a stretch past the Drive's end, fails")
    func standInShort() async throws {
        try await record()
        try standIns([1_200..<3_600], short: 1)
        #expect(verifyStandIn() == .failed([
            "Take 01, channel 1 of the stand-in at 0:00 can't be read whole on the Device.",
            "Take 01, channel 2 of the stand-in at 0:00 can't be read whole on the Device.",
        ]))

        try FileManager.default.removeItem(at: take(device).appending(path: "Stand-in 1200"))
        try standIns([1_200..<4_801])  // the last frame reads back as silence
        #expect(verifyStandIn() == .failed([
            "Take 01, channel 1 of the stand-in at 0:00 isn't all on the Drive.",
            "Take 01, channel 2 of the stand-in at 0:00 isn't all on the Drive.",
        ]))
    }

    @Test("Two stand-ins in one Take are each checked; a channel missing on the Drive is named once")
    func twoStandIns() async throws {
        try await record()
        let folders = try standIns([0..<1_200, 2_400..<4_800])
        #expect(verifyStandIn() == .passed)

        try changeSample(folders[1].appending(path: "01 USB 01.wav"), frame: 0)
        #expect(verifyStandIn() == .failed(["Take 01, channel 1 of the stand-in at 0:00 has different audio on the Drive."]))
        try changeSample(folders[1].appending(path: "01 USB 01.wav"), frame: 0)

        try change(take(drive)) { $0.usbChannels.removeLast() }
        #expect(verifyStandIn() == .failed(["Take 01, channel 2 of the stand-in is missing on the Drive."]))
    }

    @Test("No stand-in, a Drive Take.json missing, or a stand-in Take.json can't hold all fail")
    func standInRefusals() async throws {
        try await record()
        #expect(verifyStandIn() == .failed(["Take 01 has no stand-in on the Device."]))

        try standIns([1_200..<3_600])
        try change(take(device)) { $0.standIns = [.init(start: -5, end: 10)] }
        #expect(verifyStandIn() == .failed(["Take 01's Take.json lists a stand-in that can't be."]), "a negative start")
        try change(take(device)) { $0.standIns = [.init(start: 3_600, end: 1_200)] }
        #expect(verifyStandIn() == .failed(["Take 01's Take.json lists a stand-in that can't be."]), "an end before its start")
        try change(take(device)) { $0.standIns = [.init(start: 1_200, end: 3_600)] }
        #expect(verifyStandIn() == .passed)

        try FileManager.default.removeItem(at: take(drive).appending(path: "Take.json"))
        #expect(verifyStandIn() == .failed(["Take 01 is missing on the Drive."]))
    }

    @Test("A stand-in folder with files the Take doesn't list, or that is a link, or checked against itself, fails")
    func standInFolderGuards() async throws {
        try await record()
        let folder = try #require(try standIns([1_200..<3_600]).first)
        #expect(verifyStandIn(drive: take(device)) == .failed(["Take 01's Device and Drive Copies are the same folder."]))

        try writeStem(folder.appending(path: "03 USB 03.wav"), [0])
        #expect(verifyStandIn() == .failed(["Take 01's stand-in has files the Take doesn't list."]))
        try FileManager.default.removeItem(at: folder.appending(path: "03 USB 03.wav"))

        let outside = root.appending(path: "Outside")
        try FileManager.default.moveItem(at: folder, to: outside)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
        #expect(verifyStandIn() == .failed(["Take 01's stand-in isn't a folder of its own on the Device."]))
    }

    @Test("A stand-in Stem holding more on disk than its header and stretch fails: that tail was never checked (#871)")
    func standInTailPastItsHeader() async throws {
        try await record()
        let folder = try #require(try standIns([1_200..<3_600]).first)
        // An abandoned standby's write landed after its last header commit.
        let handle = try FileHandle(forUpdating: folder.appending(path: "01 USB 01.wav"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0x11, count: 100 * StemWriter.bytesPerSample))
        try handle.close()

        #expect(verifyStandIn() == .failed(["Take 01, channel 1 of the stand-in at 0:00 can't be read whole on the Device."]))
    }

    @Test("A zero-length stand-in passes only with empty Stems")
    func zeroLengthStandIn() async throws {
        try await record()
        try standIns([2_400..<2_400])
        #expect(verifyStandIn() == .passed)
    }

    @Test("A stand-in longer than one 4 MB piece is compared to its end")
    func longStandIn() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await record()
        let frames = 1_500_000
        for stem in ["01 USB 01.wav", "02 USB 02.wav"] {
            try writeStem(take(drive).appending(path: stem), (0..<frames).map { Float($0 % 1000) / 8_388_608 })
        }
        let folder = try #require(try standIns([0..<frames]).first)
        #expect(verifyStandIn() == .passed)

        try changeSample(folder.appending(path: "02 USB 02.wav"), frame: 1_450_000)
        #expect(verifyStandIn() == .failed(["Take 01, channel 2 of the stand-in at 0:00 has different audio on the Drive."]))
    }
}

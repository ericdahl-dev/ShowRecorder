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
    func record() throws {
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.arm(audio)
        for _ in 1...2 {
            try recorder.startTake()
            audio.deliver((0..<2).map { c in (0..<4_800).map { Float(($0 + c * 7) % 1000) / 8_388_608 } })
            try recorder.stopTake()
        }
        recorder.disarm()
        try recorder.endShow()
    }

    func verify() -> CopyCheck.Result { CopyCheck.verify(show: show, device: device, drive: drive) }

    @Test("A Show whose Drive Copy matches the Device Copy passes")
    func cleanShowPasses() throws {
        try record()
        #expect(verify() == .passed)
    }

    func failures(_ result: CopyCheck.Result) -> [String] {
        if case .failed(let reasons) = result { return reasons }
        return []
    }

    @Test("A Take missing on the Drive, or the whole Show missing, fails and says which")
    func missingTake() throws {
        try record()
        try FileManager.default.removeItem(at: drive.appending(path: "\(show)/Take 02"))
        #expect(failures(verify()) == ["Take 02 is missing on the Drive."])

        try FileManager.default.removeItem(at: drive.appending(path: show))
        #expect(failures(verify()) == ["The Drive doesn't have this Show."])
    }

    @Test("A Drive Copy with Gaps left fails; once Repaired it passes")
    func gaps() throws {
        try record()
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
    func stemDiffers() throws {
        try record()
        let stem1 = drive.appending(path: "\(show)/Take 01/01 USB 01.wav")
        let stem2 = drive.appending(path: "\(show)/Take 01/02 USB 02.wav")

        // Same length, one sample changed.
        let handle = try FileHandle(forUpdating: stem1)
        let region = try #require(StemLength.audioRegion(at: stem1))
        try handle.seek(toOffset: region.offset + 6)
        try handle.write(contentsOf: Data([0x7F]))
        try handle.close()
        #expect(failures(verify()) == ["Take 01, channel 1 has different audio on the Drive."])

        // Shorter.
        let cut = try FileHandle(forUpdating: stem2)
        try cut.truncate(atOffset: try #require(StemLength.audioRegion(at: stem2)).offset + 300)
        try cut.close()
        #expect(failures(verify()).contains("Take 01, channel 2 is a different length on the Drive."))

        // Gone.
        try FileManager.default.removeItem(at: stem2)
        #expect(failures(verify()).contains("Take 01, channel 2 can't be read on the Drive."))
    }

    func recorderWithDrive(_ connected: Bool = true) -> Recorder {
        let drive = drive
        return Recorder(deviceFolder: device, driveFolder: { connected ? DestinationAccess(folder: drive) : nil }, now: { RecordingTakeTests.showDay })
    }

    @Test("Deleting the Device copy after the check removes only the Device copy; a failed check, a missing Drive or an open Show deletes nothing")
    func deleteDeviceCopyAfterCheck() async throws {
        try record()

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
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([[0.1]])
        try recorder.stopTake()
        let outcome = await recorder.deleteDeviceCopy(of: show)
        #expect(outcome.deleted.isEmpty)
        #expect(FileManager.default.fileExists(atPath: device.appending(path: show).path))
    }
}

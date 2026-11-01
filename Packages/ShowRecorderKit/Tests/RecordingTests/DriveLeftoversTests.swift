import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// A Drive join that was canceled or hung leaves a Take folder on the Drive with empty Stems and no Take.json (#814). It
/// is swept when it is provably empty of audio, and only then.
@MainActor
@Suite("Leftover Drive Take folders")
struct DriveLeftoversTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "DriveLeftoversTests-\(UUID().uuidString)")
    var driveShow: URL { root.appending(path: "Drive/2026-10-06 Show") }

    func folder(_ name: String) throws -> URL {
        let folder = driveShow.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A Stem with `frames` frames in it, closed.
    func stem(_ name: String, frames: Int, in folder: URL) throws {
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        let writer = try StemWriter.open(url: folder.appending(path: name), info: info, resumingAt: nil)
        if frames > 0 { try [Float](repeating: 0.1, count: frames).withUnsafeBufferPointer { try writer.append($0) } }
        try writer.finalize()
    }

    func takeJSON(in folder: URL) throws {
        let metadata = TakeMetadata(
            show: "Show", take: 1, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        try metadata.write(to: folder)
    }

    var deviceShow: URL { root.appending(path: "Device/2026-10-06 Show") }

    /// Makes everything in `folder` look an hour old: a leftover is old; a Take being made right now is not.
    func age(_ folder: URL) throws {
        let old = Date().addingTimeInterval(-3_600)
        for url in [folder] + ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []) {
            try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: url.path)
        }
    }

    /// A leftover as a canceled join leaves it: aged, empty Stems, no Take.json.
    func leftover(_ name: String) throws {
        let folder = try folder(name)
        try stem("01 USB 01.wav", frames: 0, in: folder)
        try age(folder)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: driveShow.appending(path: name).path)
    }

    @Test("A Take folder with only empty Stems and no Take.json is swept, and so is an empty one")
    func sweepsTheEmpty() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let canceled = try folder("Take 01")
        try stem("01 USB 01.wav", frames: 0, in: canceled)
        try stem("02 USB 02.wav", frames: 0, in: canceled)
        try age(canceled)
        let empty = try folder("Take 02")
        try age(empty)
        let zeroBytes = try folder("Take 03")
        FileManager.default.createFile(atPath: zeroBytes.appending(path: "01 USB 01.wav").path, contents: Data())
        try age(zeroBytes)
        let finder = try folder("Take 04")
        try stem("01 USB 01.wav", frames: 0, in: finder)
        try Data().write(to: finder.appending(path: ".DS_Store"))
        try Data().write(to: finder.appending(path: "._01 USB 01.wav"))
        try age(finder)

        let swept = DriveLeftovers.sweep(driveShow: driveShow, deviceShow: deviceShow, upTo: 99)

        #expect(Set(swept) == ["Take 01", "Take 02", "Take 03", "Take 04"])
        #expect(!exists("Take 01") && !exists("Take 02") && !exists("Take 03") && !exists("Take 04"))
    }

    @Test("A folder with any audio, a Take.json, another file or a subfolder is left alone")
    func keepsAnythingElse() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = try folder("Take 01")
        try stem("01 USB 01.wav", frames: 480, in: audio)
        let described = try folder("Take 02")
        try stem("01 USB 01.wav", frames: 0, in: described)
        try takeJSON(in: described)
        let stray = try folder("Take 03")
        try stem("01 USB 01.wav", frames: 0, in: stray)
        try Data("notes".utf8).write(to: stray.appending(path: "notes.txt"))
        let nested = try folder("Take 04")
        _ = try FileManager.default.createDirectory(at: nested.appending(path: "Stand-in 0"), withIntermediateDirectories: true)
        let garbage = try folder("Take 05")
        try Data("not a wave file at all, but not empty".utf8).write(to: garbage.appending(path: "01 USB 01.wav"))
        let oneEmptyOneNot = try folder("Take 06")
        try stem("01 USB 01.wav", frames: 0, in: oneEmptyOneNot)
        try stem("02 USB 02.wav", frames: 10, in: oneEmptyOneNot)
        for folder in [audio, described, stray, nested, garbage, oneEmptyOneNot] { try age(folder) }

        let swept = DriveLeftovers.sweep(driveShow: driveShow, deviceShow: deviceShow, upTo: 99)

        #expect(swept.isEmpty)
        for name in ["Take 01", "Take 02", "Take 03", "Take 04", "Take 05", "Take 06"] { #expect(exists(name), "\(name) stays") }
    }

    @Test("Only folders named Take NN are looked at, not a set-aside Take or any other folder")
    func keepsOtherNames() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try folder("Take 01 (set aside)")
        _ = try folder("Notes")
        _ = try folder("Take 1")

        #expect(DriveLeftovers.sweep(driveShow: driveShow, deviceShow: deviceShow, upTo: 99).isEmpty)
        #expect(exists("Take 01 (set aside)") && exists("Notes") && exists("Take 1"))
    }

    @Test("A folder anything was written to in the last minutes is left alone: it may be a Take being made right now")
    func keepsTheYoung() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let fresh = try folder("Take 01")
        try stem("01 USB 01.wav", frames: 0, in: fresh)   // made just now, with no Take.json yet
        try leftover("Take 02")
        let oldFolderYoungStem = try folder("Take 03")
        try stem("01 USB 01.wav", frames: 0, in: oldFolderYoungStem)
        try FileManager.default.setAttributes(
            [.creationDate: Date().addingTimeInterval(-3_600), .modificationDate: Date().addingTimeInterval(-3_600)], ofItemAtPath: oldFolderYoungStem.path)

        let swept = DriveLeftovers.sweep(driveShow: driveShow, deviceShow: deviceShow, upTo: 99)

        #expect(swept == ["Take 02"])
        #expect(exists("Take 01") && exists("Take 03"))
    }

    @Test("A Take number above the Show's count is left alone: a Take starting now will be that number")
    func keepsNumbersAboveTheCount() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try leftover("Take 02")
        try leftover("Take 03")

        let swept = DriveLeftovers.sweep(driveShow: driveShow, deviceShow: deviceShow, upTo: 2)

        #expect(swept == ["Take 02"])
        #expect(exists("Take 03"))
    }

    @Test("A Take whose Device Take.json marks its Drive Copy abandoned is left for the recovery that repairs it")
    func keepsWhatRecoveryNeeds() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try leftover("Take 01")
        try leftover("Take 02")
        let deviceTake = deviceShow.appending(path: "Take 01", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: deviceTake, withIntermediateDirectories: true)
        var metadata = TakeMetadata(
            show: "Show", take: 1, startedAt: RecordingTakeTests.showDay, sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        metadata.abandonedCopies = [.drive]
        try metadata.write(to: deviceTake)

        let swept = DriveLeftovers.sweep(driveShow: driveShow, deviceShow: deviceShow, upTo: 99)

        #expect(swept == ["Take 02"])
        #expect(exists("Take 01"), "the recovery needs it")
    }

    @Test("A Take.json that lands after the folder was judged empty is never removed with it")
    func lateTakeJSONSurvives() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try folder("Take 01")
        try stem("01 USB 01.wav", frames: 0, in: folder)
        try takeJSON(in: folder)   // written after the folder was classified as a leftover

        let removed = DriveLeftovers.removeLeftover(folder)

        #expect(!removed)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: TakeMetadata.fileName).path))
    }

    @Test("A Stem that gained audio after the folder was judged empty is never removed with it")
    func lateAudioSurvives() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try folder("Take 01")
        try stem("01 USB 01.wav", frames: 480, in: folder)

        let removed = DriveLeftovers.removeLeftover(folder)

        #expect(!removed)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "01 USB 01.wav").path))
    }

    @Test("A Show folder that isn't there is nothing to sweep")
    func noShowFolder() {
        #expect(DriveLeftovers.sweep(driveShow: root.appending(path: "Nowhere"), deviceShow: deviceShow, upTo: 99).isEmpty)
    }

    @Test("The Recorder sweeps the current Show's leftovers when it looks for Copies to recover, and not during a Take")
    func recorderSweeps() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let device = root.appending(path: "Device")
        let drive = root.appending(path: "Drive")
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay }, destinationCheckInterval: nil)
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        // Two Takes with no Drive at the press: the Drive's Take folders for them are never made.
        recorder.recordTo = .device
        for _ in 0..<2 {
            try recorder.startTake()
            audio.deliver([Array(repeating: 0.25, count: 480)])
            try await recorder.stopTake()
            await recorder.waitForRepair()
        }
        let show = try #require(recorder.currentShow?.name)
        let leftover = drive.appending(path: "\(show)/Take 02", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try age(leftover)

        // During a Take the Recorder does not look.
        recorder.recordTo = .both
        try recorder.startTake()
        await recorder.recoverAbandonedCopies()
        #expect(FileManager.default.fileExists(atPath: leftover.path), "not during a Take")
        try await recorder.stopTake()
        await recorder.waitForRepair()

        // With the Drive Take for Take 03 (the one just recorded, on both Copies) in place, and Take 02's leftover old.
        await recorder.recoverAbandonedCopies()

        #expect(!FileManager.default.fileExists(atPath: leftover.path), "swept once the Take is over")
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "\(show)/Take 03").path), "the Take it recorded stays")
    }
}

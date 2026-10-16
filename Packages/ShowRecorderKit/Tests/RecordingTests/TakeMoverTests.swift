import AudioIO
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Finding the Drive only Takes the Device still holds, to move them to a Drive connected later (#630).
@MainActor
@Suite("Finding Takes to move to the Drive")
struct TakeMoverTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }
    var drive: URL { root.appending(path: "Drive") }
    let show = "2026-10-06 Show"
    func take(_ copy: URL, _ number: Int = 1) -> URL { copy.appending(path: "\(show)/\(TakeMetadata.name(take: number))") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "TakeMoverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "Drive"), withIntermediateDirectories: true)
    }

    /// Two Takes of one channel in both Copies, the Show ended.
    func record() async throws {
        let drive = drive
        let recorder = Recorder(deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        for _ in 1...2 {
            try recorder.startTake()
            audio.deliver([(0..<4_800).map { Float($0 % 1000) / 8_388_608 }])
            try await recorder.stopTake()
        }
        recorder.disarm()
        try recorder.endShow()
    }

    func change(_ folder: URL, _ edit: (inout TakeMetadata) -> Void) throws {
        var metadata = try TakeMetadata.read(fromTakeFolder: folder)
        edit(&metadata)
        try metadata.write(to: folder)
    }

    /// "Show Take kind", with a skipped Take's reason ("… skipped noDriveTake").
    func found(isDriveOnly: Bool = false, excluding: URL? = nil, driveFolder: URL? = nil) -> [String] {
        TakeMover.find(deviceFolder: device, driveFolder: driveFolder ?? drive, excluding: excluding, isDriveOnly: { _ in isDriveOnly }).map {
            switch $0.kind {
            case .skipped(let reason): "\($0.show) \($0.take) skipped \(reason)"
            default: "\($0.show) \($0.take) \($0.kind)"
            }
        }
    }

    @Test("Ordinary Takes in both Copies are never moved")
    func ordinaryTakes() async throws {
        try await record()
        #expect(found().isEmpty)
    }

    @Test("A stand-in kept on the Device is found, Drive only or not by the flag, with its folder")
    func standInKept() async throws {
        try await record()
        try change(take(device, 2)) { $0.standIns = [.init(start: 0, end: 4_800)] }

        let movable = TakeMover.find(deviceFolder: device, driveFolder: drive)

        #expect(found() == ["\(show) 2 standIn"])
        #expect(movable.map { $0.deviceFolder.resolvingSymlinksInPath().path } == [take(device, 2).resolvingSymlinksInPath().path])
    }

    @Test("A zero-length stand-in still counts, so the mover clears it")
    func zeroLengthStandIn() async throws {
        try await record()
        try change(take(device, 2)) { $0.standIns = [.init(start: 4_800, end: 4_800)] }
        #expect(found() == ["\(show) 2 standIn"])
    }

    @Test("A stand-in whose Take isn't on the Drive is skipped: its Drive was another, or the Take was deleted there")
    func standInNoDriveTake() async throws {
        try await record()
        try change(take(device, 1)) { $0.standIns = [] }
        try change(take(device, 2)) { $0.standIns = [.init(start: 0, end: 4_800)] }
        try FileManager.default.removeItem(at: take(drive, 2))

        #expect(found() == ["\(show) 2 skipped noDriveTake"])
    }

    @Test("With no Show of that name on the Drive, a stand-in is skipped and a Device-only Take is found")
    func driveShowMissing() async throws {
        try await record()
        try change(take(device, 2)) { $0.standIns = [.init(start: 0, end: 4_800)] }
        try FileManager.default.removeItem(at: drive.appending(path: show))

        #expect(found(isDriveOnly: true) == ["\(show) 1 deviceOnly", "\(show) 2 skipped noDriveTake"])
    }

    @Test("A Drive that can't be listed finds nothing")
    func driveUnlistable() async throws {
        try await record()
        try change(take(device, 2)) { $0.standIns = [.init(start: 0, end: 4_800)] }
        #expect(found(isDriveOnly: true, driveFolder: root.appending(path: "No Drive")).isEmpty)
    }

    @Test("A Drive Take folder whose Take.json can't be read is skipped as unreadable, never moved over")
    func driveTakeUnreadable() async throws {
        try await record()
        try change(take(device, 1)) { $0.standIns = [.init(start: 0, end: 4_800)] }
        try Data("not json".utf8).write(to: take(drive, 1).appending(path: "Take.json"))
        try Data("not json".utf8).write(to: take(drive, 2).appending(path: "Take.json"))

        #expect(found(isDriveOnly: true) == ["\(show) 1 skipped unreadable", "\(show) 2 skipped unreadable"])
    }

    @Test("A Drive only Take with no Drive Take is found whole on the Device")
    func deviceOnly() async throws {
        try await record()
        try FileManager.default.removeItem(at: take(drive, 2))

        #expect(found(isDriveOnly: true) == ["\(show) 1 redundant", "\(show) 2 deviceOnly"])
        #expect(found(isDriveOnly: false).isEmpty, "not Drive only: left alone")
    }

    @Test("A Drive Take of the same number from another recording is a clash: skipped, stand-in or not")
    func clash() async throws {
        try await record()
        try change(take(drive, 1)) { $0.startedAt = $0.startedAt.addingTimeInterval(60) }
        try change(take(drive, 2)) { $0.startedAt = $0.startedAt.addingTimeInterval(60) }
        try change(take(device, 2)) { $0.standIns = [.init(start: 0, end: 4_800)] }

        #expect(found(isDriveOnly: true) == ["\(show) 1 skipped anotherRecording", "\(show) 2 skipped anotherRecording"])
    }

    @Test("A Drive Take with Gaps left is found to be finished from the Device; one with a failed Repair is skipped")
    func driveHasGaps() async throws {
        try await record()
        try change(take(drive, 1)) { $0.gaps = [.init(copy: .drive, start: 0, end: 10)] }
        try change(take(drive, 2)) {
            $0.gaps = [.init(copy: .drive, start: 0, end: 10)]
            $0.repairs = [.init(copy: .drive, start: 0, end: 10, outcome: .failed)]
        }
        #expect(found(isDriveOnly: true) == ["\(show) 1 redundant", "\(show) 2 skipped driveHasGaps"])

        try change(take(drive, 1)) { $0.repairs = [.init(copy: .drive, start: 0, end: 10, outcome: .repaired)] }
        #expect(found(isDriveOnly: true).first == "\(show) 1 redundant")
    }

    @Test("Every Show on the Device is scanned, in Show then Take order")
    func everyShow() async throws {
        try await record()
        try FileManager.default.copyItem(at: device.appending(path: show), to: device.appending(path: "2026-10-01 Show"))
        try FileManager.default.copyItem(at: drive.appending(path: show), to: drive.appending(path: "2026-10-01 Show"))

        #expect(found(isDriveOnly: true) == ["2026-10-01 Show 1 redundant", "2026-10-01 Show 2 redundant", "\(show) 1 redundant", "\(show) 2 redundant"])
    }

    @Test("Hidden or linked Show and Take folders, misnamed Take folders and loose files are never returned")
    func onlyRealTakeFolders() async throws {
        try await record()
        let fm = FileManager.default
        try Data().write(to: device.appending(path: "notes.txt"))
        try fm.copyItem(at: device.appending(path: show), to: device.appending(path: ".2026-10-02 Show"))
        try fm.createSymbolicLink(at: device.appending(path: "2026-10-03 Show"), withDestinationURL: device.appending(path: show))
        try fm.copyItem(at: take(device, 1), to: device.appending(path: "\(show)/.Take 01"))
        try fm.copyItem(at: take(device, 1), to: device.appending(path: "\(show)/Take 01 copy"))
        try fm.moveItem(at: take(device, 2), to: root.appending(path: "Take 02"))
        try fm.createSymbolicLink(at: take(device, 2), withDestinationURL: root.appending(path: "Take 02"))

        #expect(found(isDriveOnly: true) == ["\(show) 1 redundant"])
    }

    @Test("The running Take's folder is left out")
    func runningTakeExcluded() async throws {
        try await record()
        #expect(found(isDriveOnly: true, excluding: take(device, 2)) == ["\(show) 1 redundant"])
    }
}

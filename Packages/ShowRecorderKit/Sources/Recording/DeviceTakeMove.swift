import BroadcastWave
import Destinations
import Foundation
import TakeFile

/// Drive only (#196, ADR 0006, #630): moves a Drive only Take the Device holds whole to the Drive, then removes the
/// Device's Take. With no Take on the Drive yet, it makes one there: `Take.json` first, saying the Drive is missing all
/// of it (a Gap over the whole Take), then empty Stems that Repair fills from the Device. A Take the Drive already holds
/// is only checked. Nothing is removed until `CopyCheck.verifyTake` passes, before and after the Device's Take is set
/// aside; any check that fails keeps the Device's Take and says why.
enum DeviceTakeMove {
    /// Moves the Device's Take at `deviceTake` to the Drive's at `driveTake`. Synchronous file I/O: call it off the main
    /// actor. `shouldStop` is asked before each Stem and before the Device's Take is set aside; a Drive Take this run
    /// made is removed again when it stops before the Take is all there. `hook` lets tests act at a `Step`.
    static func run(
        deviceTake: URL, driveTake: URL, shouldStop: () -> Bool, at hook: (StandInMove.Step) -> Void = { _ in }
    ) -> StandInMove.Outcome {
        let name = deviceTake.lastPathComponent
        let fm = FileManager.default
        guard fm.fileExists(atPath: deviceTake.path) else { return .gone }
        guard ShowDeleter.isRealFolder(deviceTake), let metadata = try? TakeMetadata.read(fromTakeFolder: deviceTake) else {
            return .kept(["\(name) can't be read on the Device."])
        }
        // The Device's Take holds its Take.json and Stems, nothing else that the move would delete with it.
        let expected = Set([TakeMetadata.fileName, ".DS_Store"] + metadata.usbChannels.map(\.stemFile))
        guard let contents = try? fm.contentsOfDirectory(atPath: deviceTake.path) else { return .kept(["\(name) can't be read on the Device."]) }
        let others = Set(contents).subtracting(expected)
        guard others.isEmpty else { return .kept(["\(name) on the Device holds other files too: \(others.sorted().joined(separator: ", "))."]) }

        // A Drive Take this run makes still has to record its Repair, once the check has passed; until then a failure
        // removes it again.
        var made: Made?
        if (try? fm.attributesOfItem(atPath: driveTake.path)) == nil {
            if let problem = problemBeforeCopying(metadata, from: deviceTake, to: driveTake) { return .kept([problem]) }
            switch copy(metadata, from: deviceTake, to: driveTake, shouldStop: shouldStop) {
            case .success(let filled): made = filled
            case .failure(let failure): return failure.outcome
            }
            hook(.filled)
        }
        // A Drive Take left with Gaps not yet repaired (a move or Stop's Repair a crash cut off): its known Gaps are filled
        // from the Device's whole Copy, and nothing else on the Drive is written.
        var finished: TakeMetadata?
        if made == nil {
            switch fillKnownGaps(metadata, from: deviceTake, to: driveTake, shouldStop: shouldStop) {
            case .success(let filled): finished = filled
            case .failure(let failure): return failure.outcome
            }
        }
        // The pair check comes first: two different recordings, links or one folder twice are never compared or written.
        let recording = made?.metadata ?? finished
        guard let check = CopyCheck.verifyTake(device: deviceTake, drive: driveTake, checksDriveOutcome: recording == nil, shouldStop: shouldStop) else {
            made?.discard(driveTake)
            return .stopped
        }
        if case .failed(let reasons) = check {
            made?.discard(driveTake)
            return .kept(reasons)
        }
        if let recording {
            guard (try? recording.write(to: driveTake)) != nil else {
                made?.discard(driveTake)
                return .kept(["\(name)'s Take.json couldn't be written on the Drive."])
            }
            if recording.repairs.contains(where: { $0.outcome == .failed }) {
                made?.discard(driveTake)
                return .kept(["\(name) couldn't be copied whole to the Drive."])
            }
        }
        if shouldStop() { return .stopped }

        let setAsideName = StandInMove.setAsideName(of: deviceTake)
        let setAside = deviceTake.deletingLastPathComponent().appending(path: setAsideName, directoryHint: .isDirectory)
        guard !fm.fileExists(atPath: setAside.path) else { return .kept(["A folder \(setAsideName) from an earlier move is in the way on the Device."]) }
        guard (try? fm.moveItem(at: deviceTake, to: setAside)) != nil else { return .kept(["\(name) couldn't be set aside on the Device."]) }
        hook(.setAside)
        // Once more, against what is now set aside, before anything is deleted. Stopped, it is undone for a later move.
        let second = CopyCheck.verifyTake(device: setAside, drive: driveTake, shouldStop: shouldStop)
        if second != .passed {
            var reasons: [String] = []
            if case .failed(let problems) = second { reasons = problems }
            if fm.fileExists(atPath: deviceTake.path) || (try? fm.moveItem(at: setAside, to: deviceTake)) == nil {
                return .kept(reasons + ["\(name) couldn't be put back on the Device; it is in \(setAsideName)."])
            }
            return second == nil ? .stopped : .kept(reasons)
        }
        hook(.removing)
        guard (try? fm.removeItem(at: setAside)) != nil else {
            return .kept(["\(name) is on the Drive, but \(setAsideName) couldn't be removed from the Device."])
        }
        return .moved
    }

    /// What `copy` reports when it doesn't finish.
    struct Failure: Error {
        let outcome: StandInMove.Outcome
        init(_ outcome: StandInMove.Outcome) { self.outcome = outcome }
    }

    /// A Drive Take a move made: its Take.json with the Repair, and whether the move made its Show folder too.
    struct Made {
        var metadata: TakeMetadata
        var madeShow: Bool

        /// Removes the Drive Take this move made, and its Show folder when the move made that too and it holds nothing
        /// else now.
        func discard(_ driveTake: URL) {
            let fm = FileManager.default
            try? fm.removeItem(at: driveTake)
            let driveShow = driveTake.deletingLastPathComponent()
            guard madeShow, let left = try? fm.contentsOfDirectory(atPath: driveShow.path),
                  Set(left).isSubset(of: [ShowFile.fileName, ".DS_Store"]) else { return }
            try? fm.removeItem(at: driveShow)
        }
    }

    /// A channel whose Stem on the Device is shorter than the rest of the Take, if one is: a Take a crash cut off doesn't
    /// hold all of itself.
    private static func shortChannel(_ metadata: TakeMetadata, in deviceTake: URL) -> String? {
        let lengths = metadata.usbChannels.map { ($0.usbChannel, (try? StemFile.inspect(deviceTake.appending(path: $0.stemFile)))?.framesOnDisk ?? 0) }
        let longest = lengths.map(\.1).max() ?? 0
        guard let short = lengths.first(where: { $0.1 < longest }) else { return nil }
        return "\(deviceTake.lastPathComponent), channel \(short.0) is shorter than the rest of the Take on the Device."
    }

    /// Fills the Drive Take's Gaps not yet repaired from the Device's whole Copy, one Stem at a time, through Repair.
    /// Returns the Drive's Take.json with that Repair, to write once the copy is checked; nil when the Drive has no such
    /// Gap; or what to report. Nothing is written before the two are checked to be the same recording, the Device's Stems
    /// all one length and named on the Drive as on the Device.
    private static func fillKnownGaps(
        _ metadata: TakeMetadata, from deviceTake: URL, to driveTake: URL, shouldStop: () -> Bool
    ) -> Result<TakeMetadata?, Failure> {
        let name = deviceTake.lastPathComponent
        guard var onDrive = try? TakeMetadata.read(fromTakeFolder: driveTake) else { return .success(nil) }
        // The Gaps the Drive is known to miss: its own, and the Drive Gaps only the Device's Take.json lists. Stop leaves a Copy
        // it gave up on with the Take.json it had at the start, so the Gaps of its tail are on the Device alone (#668);
        // `StandInMove` merges them the same way. They enter the Drive's Take.json only if the check passes (`run` writes it).
        let deviceOnly = metadata.gaps.reduce(into: [TakeMetadata.Gap]()) { found, gap in
            if gap.copy == .drive, !onDrive.gaps.contains(gap), !found.contains(gap) { found.append(gap) }
        }
        let unrepaired = (onDrive.gaps + deviceOnly).filter { gap in
            gap.copy == .drive && !onDrive.repairs.contains { $0.copy == .drive && $0.start == gap.start && $0.end == gap.end && $0.outcome == .repaired }
        }
        guard !unrepaired.isEmpty else { return .success(nil) }
        if let problem = CopyCheck.takePairProblem(device: deviceTake, drive: driveTake) { return .failure(.init(.kept([problem]))) }
        if let problem = shortChannel(metadata, in: deviceTake) { return .failure(.init(.kept([problem]))) }
        for channel in metadata.usbChannels where !onDrive.usbChannels.contains(where: { $0.usbChannel == channel.usbChannel && $0.stemFile == channel.stemFile }) {
            return .failure(.init(.kept(["\(name), channel \(channel.usbChannel) isn't under the same name on the Drive."])))
        }
        // Only the Drive's unrepaired Gaps are filled; the Device's own Gaps say where it hasn't the audio either.
        var known = onDrive
        known.gaps = unrepaired + (metadata.gaps + onDrive.gaps).filter { $0.copy == .device }
        let copies = [TakeRepair.Copy(kind: .device, folder: deviceTake), TakeRepair.Copy(kind: .drive, folder: driveTake)]
        var repairs: [TakeMetadata.Repair] = []
        for channel in metadata.usbChannels {
            if shouldStop() { return .failure(.init(.stopped)) }
            var one = known
            one.usbChannels = [channel]
            let filled = TakeRepair.fill(copies: copies, metadata: one, skip: [.device], shouldStop: shouldStop)
            // Stopped within the Stem: nothing is recorded, so its Gaps are filled by a later move.
            if shouldStop() { return .failure(.init(.stopped)) }
            for repair in filled {
                if let index = repairs.firstIndex(where: { $0.copy == repair.copy && $0.start == repair.start && $0.end == repair.end }) {
                    if repair.outcome == .failed { repairs[index].outcome = .failed }
                } else {
                    repairs.append(repair)
                }
            }
        }
        onDrive.gaps += deviceOnly
        onDrive.repairs = onDrive.repairs.filter { old in !repairs.contains { $0.copy == old.copy && $0.start == old.start && $0.end == old.end } }
            + repairs
        return .success(onDrive)
    }

    /// Why nothing should be made on the Drive for the Device's Take, if so: Stems of unequal length (a Take a crash
    /// cut off doesn't hold all of itself), a Drive Show that isn't a folder of its own, or whose Show.json can't be
    /// read or is another Show's.
    private static func problemBeforeCopying(_ metadata: TakeMetadata, from deviceTake: URL, to driveTake: URL) -> String? {
        let name = deviceTake.lastPathComponent
        let fm = FileManager.default
        if let problem = shortChannel(metadata, in: deviceTake) { return problem }
        // Nothing is written to the Drive through a link or into something that isn't a folder of its own.
        let driveShow = driveTake.deletingLastPathComponent()
        guard (try? fm.attributesOfItem(atPath: driveShow.path)) != nil else { return nil }
        guard ShowDeleter.isRealFolder(driveShow) else { return "\(name)'s Show isn't a folder of its own on the Drive." }
        guard (try? fm.attributesOfItem(atPath: driveShow.appending(path: ShowFile.fileName).path)) != nil else { return nil }
        guard let onDrive = ShowFile.read(from: driveShow) else { return "\(name)'s Show.json on the Drive can't be read." }
        if let onDevice = ShowFile.read(from: deviceTake.deletingLastPathComponent()), onDevice.startedAt != onDrive.startedAt {
            return "\(name)'s Show on the Drive is another Show of the same name."
        }
        return nil
    }

    /// Makes the Drive's Take at `driveTake` from the Device's and fills it through Repair, one Stem at a time. Returns
    /// the Drive's Take.json with its Repair, to write once the copy is checked; or what to report, with the Drive Take
    /// it made removed again.
    private static func copy(
        _ metadata: TakeMetadata, from deviceTake: URL, to driveTake: URL, shouldStop: () -> Bool
    ) -> Result<Made, Failure> {
        let name = deviceTake.lastPathComponent
        let fm = FileManager.default
        let driveShow = driveTake.deletingLastPathComponent()
        var made = Made(metadata: metadata, madeShow: (try? fm.attributesOfItem(atPath: driveShow.path)) == nil)
        do {
            try fm.createDirectory(at: driveShow, withIntermediateDirectories: true)
            // A Show.json already there is never written over.
            if (try? fm.attributesOfItem(atPath: driveShow.appending(path: ShowFile.fileName).path)) == nil {
                try ShowFile.read(from: deviceTake.deletingLastPathComponent())?.write(to: driveShow)
            }
            try fm.createDirectory(at: driveTake, withIntermediateDirectories: false)
        } catch {
            made.discard(driveTake)
            return .failure(.init(.kept(["\(name) couldn't be made on the Drive."])))
        }
        // The Drive's Take.json comes first and says the Drive has none of the Take, so a Take cut short says so.
        let length = metadata.usbChannels.map { Int((try? StemFile.inspect(deviceTake.appending(path: $0.stemFile)))?.framesOnDisk ?? 0) }.max() ?? 0
        var onDrive = metadata
        onDrive.gaps.append(.init(copy: .drive, start: 0, end: length))
        do {
            try onDrive.write(to: driveTake)
            for channel in metadata.usbChannels {
                let info = StemWriter.Info(
                    sampleRate: metadata.sampleRate, description: channel.name, originator: "ShowRecorder",
                    timeReference: metadata.timeReference, originationDate: metadata.startedAt)
                try StemWriter(url: driveTake.appending(path: channel.stemFile), info: info).finalize()
            }
        } catch {
            made.discard(driveTake)
            return .failure(.init(.kept(["\(name) couldn't be written on the Drive."])))
        }
        // Repair one Stem at a time, so a Take started meanwhile stops it between Stems.
        let copies = [TakeRepair.Copy(kind: .device, folder: deviceTake), TakeRepair.Copy(kind: .drive, folder: driveTake)]
        var repairs: [TakeMetadata.Repair] = []
        for channel in metadata.usbChannels {
            if shouldStop() {
                made.discard(driveTake)
                return .failure(.init(.stopped))
            }
            var one = onDrive
            one.usbChannels = [channel]
            let filled = TakeRepair.fill(copies: copies, metadata: one, skip: [.device], shouldStop: shouldStop)
            if shouldStop() {
                made.discard(driveTake)
                return .failure(.init(.stopped))
            }
            for repair in filled {
                if let index = repairs.firstIndex(where: { $0.copy == repair.copy && $0.start == repair.start && $0.end == repair.end }) {
                    if repair.outcome == .failed { repairs[index].outcome = .failed }
                } else {
                    repairs.append(repair)
                }
            }
        }
        onDrive.repairs = metadata.repairs + repairs
        made.metadata = onDrive
        return .success(made)
    }
}

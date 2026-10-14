import Destinations
import Foundation
import TakeFile

/// Drive only (#196, ADR 0006, #630): finishes or undoes a move that a crash cut off after it set the Device's Take
/// aside (`.moved Take NN`) and before it deleted it. The set-aside Take is checked against its Drive Take again, in
/// full: if the Drive still holds it, the move is finished (it is deleted, and a stand-in still listed on the Drive is
/// cleared); otherwise it is put back as `Take NN`, with a stand-in listed on the Drive again. Nothing is deleted
/// unless that check passes, and nothing is touched when `Take NN` is on the Device too.
enum MoveRecovery {
    /// Every Show on the Device, against the Drive's Shows in `driveFolder`. Synchronous file I/O: call it off the main
    /// actor, with the Drive reachable. `shouldStop` is asked before each set-aside Take: a Take started meanwhile stops
    /// it, and the rest are left for the next move.
    static func run(deviceFolder: URL, driveFolder: URL, shouldStop: () -> Bool = { false }) -> [StandInMove.Result] {
        let fm = FileManager.default
        let shows = ((try? fm.contentsOfDirectory(at: deviceFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") && ShowDeleter.isRealFolder($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var results: [StandInMove.Result] = []
        for show in shows {
            let names = ((try? fm.contentsOfDirectory(atPath: show.path)) ?? []).sorted()
            for name in names {
                guard let take = takeNumber(setAside: name) else { continue }
                if shouldStop() { return results }
                let setAside = show.appending(path: name, directoryHint: .isDirectory)
                guard ShowDeleter.isRealFolder(setAside) else { continue }
                let deviceTake = show.appending(path: TakeMetadata.name(take: take), directoryHint: .isDirectory)
                let driveTake = driveFolder.appending(path: show.lastPathComponent).appending(path: TakeMetadata.name(take: take))
                let outcome = recover(setAside: setAside, deviceTake: deviceTake, driveTake: driveTake)
                results.append(.init(show: show.lastPathComponent, take: take, outcome: outcome))
            }
        }
        return results
    }

    /// The Take number of a folder named exactly `.moved Take NN` (as `StandInMove.setAsideName` makes it), else nil.
    static func takeNumber(setAside name: String) -> Int? {
        let prefix = ".moved Take "
        guard name.hasPrefix(prefix), let take = Int(name.dropFirst(prefix.count)), take > 0,
              name == StandInMove.setAsideName(of: URL(filePath: TakeMetadata.name(take: take))) else { return nil }
        return take
    }

    /// What `setAside` holds besides its Take.json and its Stems, or its listed stand-in folders (`.DS_Store` aside), in
    /// order; nil when it can't be listed.
    private static func otherFiles(in setAside: URL, metadata: TakeMetadata?, standIns: [TakeMetadata.StandIn]?) -> [String]? {
        guard let metadata, let contents = try? FileManager.default.contentsOfDirectory(atPath: setAside.path) else { return nil }
        let own = standIns.map { $0.map(\.folderName) } ?? metadata.usbChannels.map(\.stemFile)
        return Set(contents).subtracting([TakeMetadata.fileName, ".DS_Store"] + own).sorted()
    }

    private static func recover(setAside: URL, deviceTake: URL, driveTake: URL) -> StandInMove.Outcome {
        let fm = FileManager.default
        let name = deviceTake.lastPathComponent
        let setAsideName = setAside.lastPathComponent
        if (try? fm.attributesOfItem(atPath: deviceTake.path)) != nil {
            return .kept(["Both \(name) and \(setAsideName) are on the Device; neither was touched."])
        }
        let metadata = try? TakeMetadata.read(fromTakeFolder: setAside)
        let standIns = metadata?.standIns.flatMap { $0.isEmpty ? nil : $0 }
        var check = standIns != nil
            ? CopyCheck.verifyStandIn(deviceTake: setAside, driveTake: driveTake)
            : CopyCheck.verifyTake(device: setAside, drive: driveTake)
        // The folder holds the Take and nothing else that deleting it would delete with it.
        if case .passed = check {
            if let others = otherFiles(in: setAside, metadata: metadata, standIns: standIns) {
                if !others.isEmpty {
                    check = .failed(["\(setAsideName) on the Device holds other files too: \(others.joined(separator: ", "))."])
                }
            } else {
                check = .failed(["\(setAsideName) on the Device can't be listed."])
            }
        }
        guard case .passed = check else {
            var reasons: [String] = []
            if case .failed(let problems) = check { reasons = problems }
            guard (try? fm.moveItem(at: setAside, to: deviceTake)) != nil else {
                return .kept(reasons + ["\(name) couldn't be put back on the Device; it is in \(setAsideName)."])
            }
            // Put back, the stand-in is listed on the Drive again if the move had cleared it there.
            if let metadata, let standIns, var onDrive = try? TakeMetadata.read(fromTakeFolder: driveTake),
               onDrive.take == metadata.take, onDrive.startedAt == metadata.startedAt, onDrive.standIns == nil {
                onDrive.standIns = standIns
                if (try? onDrive.write(to: driveTake)) == nil { reasons.append("\(name)'s stand-in couldn't be listed again in the Drive's Take.json.") }
            }
            return .kept(reasons)
        }
        if standIns != nil, var onDrive = try? TakeMetadata.read(fromTakeFolder: driveTake), onDrive.standIns != nil {
            onDrive.standIns = nil
            guard (try? onDrive.write(to: driveTake)) != nil else {
                return .kept(["\(name)'s Take.json couldn't be written on the Drive; \(setAsideName) stays on the Device."])
            }
        }
        guard (try? fm.removeItem(at: setAside)) != nil else {
            return .kept(["\(name) is on the Drive, but \(setAsideName) couldn't be removed from the Device."])
        }
        return .moved
    }
}

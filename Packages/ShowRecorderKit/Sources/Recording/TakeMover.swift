import Destinations
import Foundation

/// Drive only (#196, ADR 0006, #630): finds the Takes whose audio the Device still holds for the Drive, to move them
/// once a Drive is connected. Only reads `Take.json` files; moves nothing.
public enum TakeMover {
    public struct Movable: Equatable, Sendable {
        /// What a found Take is. `.standIn`, `.deviceOnly` and `.redundant` only nominate a Take: the mover checks it
        /// with `CopyCheck.verifyStandIn` (a stand-in) or `CopyCheck.verifyTake` (a whole Take) before removing anything.
        public enum Kind: Equatable, Sendable {
            /// A stand-in kept on the Device: its stretches still have to reach the Drive.
            case standIn
            /// A Drive only Take recorded with no Drive: the Device holds all of it and the Drive none.
            case deviceOnly
            /// A Drive only Take the Drive already holds whole: the Device's Copy is left over.
            case redundant
            /// Left where it is.
            case skipped(SkipReason)
        }

        public enum SkipReason: Equatable, Sendable {
            /// The Drive's Take of that number was recorded at another time.
            case anotherRecording
            /// The Drive's Take still has Gaps, or its Repair failed.
            case driveHasGaps
            /// A stand-in whose Take isn't on this Drive: its Drive was another one, or the Take was deleted there.
            case noDriveTake
            /// The Drive's Take folder is there but its `Take.json` can't be read.
            case unreadable
        }

        public var show: String
        public var take: Int
        /// The Take's folder on the Device.
        public var deviceFolder: URL
        public var kind: Kind
    }

    /// Every Show on the Device, in Show then Take order. Synchronous file I/O: call it off the main actor.
    /// - Parameters:
    ///   - excluding: the running Take's Device folder, which is never returned.
    ///   - isDriveOnly: whether a Take was recorded Drive only: its `driveOnly` field by default. A Take with stand-ins
    ///     always is. A Take recorded before that field existed has none, so it stays an ordinary Device Copy.
    public static func find(
        deviceFolder: URL, driveFolder: URL, excluding: URL? = nil, isDriveOnly: (TakeMetadata) -> Bool = { $0.driveOnly == true }
    ) -> [Movable] {
        let fm = FileManager.default
        // A Drive that can't be listed tells nothing about its Takes (like ShowList's unreadable Drive).
        guard (try? fm.contentsOfDirectory(atPath: driveFolder.path)) != nil else { return [] }
        let excluded = excluding?.resolvingSymlinksInPath().path
        let shows = ((try? fm.contentsOfDirectory(at: deviceFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") && ShowDeleter.isRealFolder($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var found: [Movable] = []
        for showFolder in shows {
            let show = showFolder.lastPathComponent
            let takes = ShowList.takeMetadata(in: showFolder).filter { folder, take in
                folder.lastPathComponent == TakeMetadata.name(take: take.take) && ShowDeleter.isRealFolder(folder)
                    && folder.resolvingSymlinksInPath().path != excluded
            }
            for (folder, take) in takes.sorted(by: { $0.take.take < $1.take.take }) {
                let hasStandIn = take.standIns?.isEmpty == false
                guard hasStandIn || isDriveOnly(take) else { continue }
                let driveTakeFolder = driveFolder.appending(path: show).appending(path: folder.lastPathComponent)
                let driveTakeExists = fm.fileExists(atPath: driveTakeFolder.path)
                let driveTake = try? TakeMetadata.read(fromTakeFolder: driveTakeFolder)
                let kind: Movable.Kind
                if driveTakeExists, driveTake == nil {
                    kind = .skipped(.unreadable)
                } else if let driveTake, driveTake.startedAt != take.startedAt {
                    kind = .skipped(.anotherRecording)
                } else if hasStandIn {
                    // A standby exists only where a Drive was: with no Take there, moving would split the Take.
                    kind = driveTake == nil ? .skipped(.noDriveTake) : .standIn
                } else if let driveTake {
                    let outcome = driveTake.outcome(ofCopy: .drive)
                    kind = outcome == .hasGaps || outcome == .repairFailed ? .skipped(.driveHasGaps) : .redundant
                } else {
                    kind = .deviceOnly
                }
                found.append(Movable(show: show, take: take.take, deviceFolder: folder, kind: kind))
            }
        }
        return found
    }
}

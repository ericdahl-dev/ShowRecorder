import BroadcastWave
import Destinations
import Foundation
import TakeFile

/// Finishes a Drive Copy that Stop gave up on (#320, #817), once its Drive is back. Stop marks such a Copy in the Device's
/// `Take.json` (`abandonedCopies`); its Stems may be unfinalized, with a header shorter than the audio that reached the Drive.
///
/// - Each Drive Stem's header is rewritten to cover the whole samples on disk (as for a Take cut off by a crash).
/// - The Drive Copy's Gaps are worked out again: the tail Stop recorded, from the length the last header commit made
///   durable, becomes the tail after what is really there. Repair then fills it from the Device Copy.
/// - The marker is cleared in both Take.json files, so each Take is finished once.
///
/// A Take is left marked, to wait for its Drive, when its Drive folder isn't reachable, when the Drive's Take.json is another
/// Take's (a different Drive with the same Show and Take number), or when a Stem can't be read. A Take this launch
/// abandoned is skipped by number (`skipping`): its writer thread may still be alive and writing, so its Stems aren't touched
/// until the next launch. Only the Takes with a Device folder are found; a Drive only Take whose Device folder Stop removed
/// is not (the marker would be on the Drive alone).
enum AbandonedCopyRecovery {
    /// The Takes of the Show at `deviceShow` finished, with their Drive Take folders in `driveShow`, in Take order.
    static func finish(deviceShow: URL, driveShow: URL, skipping: Set<Int> = []) -> [CutOffTake.Found] {
        let fm = FileManager.default
        let numbers = ((try? fm.contentsOfDirectory(atPath: deviceShow.path)) ?? [])
            .compactMap { $0.hasPrefix("Take ") ? Int($0.dropFirst(5)) : nil }.sorted()
        var found: [CutOffTake.Found] = []
        for number in numbers where !skipping.contains(number) {
            let name = TakeMetadata.name(take: number)
            let deviceTake = deviceShow.appending(path: name, directoryHint: .isDirectory)
            let driveTake = driveShow.appending(path: name, directoryHint: .isDirectory)
            guard var metadata = try? TakeMetadata.read(fromTakeFolder: deviceTake),
                  let marked = metadata.abandonedCopies, marked.contains(.drive),
                  fm.fileExists(atPath: driveTake.path) else { continue }
            // The same Take: a Drive that has its own Take.json for this Take number must agree on when it began.
            if let onDrive = try? TakeMetadata.read(fromTakeFolder: driveTake),
               onDrive.startedAt != metadata.startedAt || onDrive.timeReference != metadata.timeReference { continue }
            let info = StemWriter.Info(
                sampleRate: metadata.sampleRate, description: "", originator: "ShowRecorder",
                timeReference: metadata.timeReference, originationDate: metadata.startedAt)
            // The frames every Stem has: a Copy is as long as its shortest Stem.
            // (Shorter than CutOffTake's longest: Repair fills a longer Stem's extra from the Device.) Nil when a Stem can't be read.
            func frames(in folder: URL) -> Int? {
                let lengths = metadata.usbChannels.compactMap { CutOffTake.finishStem(at: folder.appending(path: $0.stemFile), info: info) }
                return lengths.isEmpty || lengths.count != metadata.usbChannels.count ? nil : Int(lengths.min() ?? 0)
            }
            guard let driveFrames = frames(in: driveTake) else { continue }
            // The Take's length: the Device's Stems, or for a Drive only Take its stand-ins, whichever the Drive falls short of.
            let takeEnd = max(driveFrames, frames(in: deviceTake) ?? 0, metadata.standIns?.map(\.end).max() ?? 0)
            // The tail Stop recorded (it reaches the Take's end) is replaced below. A data Gap (a Dropout, late-join silence) that
            // runs past what the Drive has is clipped to it, and one that starts past it is covered by the new tail.
            metadata.gaps = metadata.gaps.compactMap { gap in
                guard gap.copy == .drive else { return gap }
                if gap.end >= takeEnd || gap.start >= driveFrames { return nil }
                return gap.end > driveFrames ? .init(copy: .drive, start: gap.start, end: driveFrames) : gap
            }
            if driveFrames < takeEnd { metadata.gaps.append(.init(copy: .drive, start: driveFrames, end: takeEnd)) }
            let remaining = marked.filter { $0 != .drive }
            metadata.abandonedCopies = remaining.isEmpty ? nil : remaining
            try? metadata.write(to: deviceTake)
            try? metadata.write(to: driveTake)
            let seconds = metadata.sampleRate > 0 ? Double(takeEnd) / Double(metadata.sampleRate) : 0
            found.append(.init(
                metadata: metadata, folders: [.device: deviceTake, .drive: driveTake],
                endedAt: metadata.startedAt.addingTimeInterval(seconds)))
        }
        return found
    }
}

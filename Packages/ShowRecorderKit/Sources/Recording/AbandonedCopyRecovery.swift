import BroadcastWave
import Destinations
import Foundation
import TakeFile

/// Finishes a Drive Copy that Stop gave up on (#320, #817) or whose write failed (#854), once its Drive is back. Stop marks such
/// a Copy in the Device's `Take.json` (`abandonedCopies`); its Stems may be unfinalized, with a header shorter than the audio that reached the Drive.
///
/// - Each Drive Stem's header is rewritten to cover the whole samples on disk (as for a Take cut off by a crash).
/// - The Drive Copy's Gaps are worked out again: the tail Stop recorded, from the length the last header commit made
///   durable, now starts at the smaller of that and what is really on disk (bytes past the last commit may be torn or zeroed).
///   Repair then fills it from the Device Copy.
/// - The marker is cleared in both Take.json files, so each Take is finished once.
///
/// A Take is left marked, to wait for its Drive, when its Drive folder isn't reachable, when the Drive's Take.json is another
/// Take's (a different Drive with the same Show and Take number), or when a Stem can't be read. A Take this launch
/// abandoned is skipped by number (`skipping`): its writer thread may still be alive and writing, so its Stems aren't touched
/// until the next launch. A Take with no Device folder (a Drive only Take whose Device folder Stop removed: the marker is on
/// the Drive alone) is found too, if its number is within the Show's Take count, but only when its Take.json recorded a
/// tail: otherwise nothing says it is short. It gets no Repair, since nothing is left to fill it from.
enum AbandonedCopyRecovery {
    /// The Takes of the Show at `deviceShow` finished, with their Drive Take folders in `driveShow`, in Take order.
    static func finish(deviceShow: URL, driveShow: URL, skipping: Set<Int> = [], upTo takeCount: Int = .max) -> [CutOffTake.Found] {
        let fm = FileManager.default
        // From both Shows: a Drive only Take whose Device folder Stop removed has its marker on the Drive alone.
        let numbers = Set(((try? fm.contentsOfDirectory(atPath: deviceShow.path)) ?? []) + ((try? fm.contentsOfDirectory(atPath: driveShow.path)) ?? []))
            .compactMap { $0.hasPrefix("Take ") ? Int($0.dropFirst(5)) : nil }.sorted()
        var found: [CutOffTake.Found] = []
        for number in numbers where !skipping.contains(number) {
            let name = TakeMetadata.name(take: number)
            let deviceTake = deviceShow.appending(path: name, directoryHint: .isDirectory)
            let driveTake = driveShow.appending(path: name, directoryHint: .isDirectory)
            let hasDevice = fm.fileExists(atPath: deviceTake.path)
            // The Device's Take.json, or the Drive's only when the Device has no folder for the Take (and its number is the Show's).
            // An unreadable Device Take.json is not replaced by the Drive's.
            guard var metadata = hasDevice ? (try? TakeMetadata.read(fromTakeFolder: deviceTake))
                    : (number <= takeCount ? (try? TakeMetadata.read(fromTakeFolder: driveTake)) : nil),
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
            // With no Device Copy, the tail Stop recorded says where the Take ended; with none recorded, nothing says it is short.
            let recordedEnd = metadata.gaps.filter { $0.copy == .drive }.map(\.end).max() ?? 0
            if !hasDevice, recordedEnd == 0 { continue }
            guard let driveFrames = frames(in: driveTake) else { continue }
            // The Take's length: the Device's Stems, or for a Drive only Take its stand-ins, whichever the Drive falls short of.
            let takeEnd = max(driveFrames, (hasDevice ? frames(in: deviceTake) : nil) ?? 0, metadata.standIns?.map(\.end).max() ?? 0, hasDevice ? 0 : recordedEnd)
            // A Drive Copy whose write failed was repaired at Stop if its Drive was still there (#854): when its Stems are whole, the
            // Gaps and what Repair did about them are the record, and stay. A short Stem makes those repairs stale: Repair redoes them.
            let repairedWhole = driveFrames >= takeEnd && metadata.repairs.contains { $0.copy == .drive }
            // Only what Stop confirmed is trusted (the tail is the Drive Gap that reaches the end Stop knew of): bytes past the tail's recorded start (the last header commit) may be zeroed or
            // torn, so the tail starts at the smaller of that and the file's real end (Eric, 2026-10-20). Repair fills the rest.
            let trusted = min(driveFrames, metadata.gaps.filter { $0.copy == .drive && $0.end >= recordedEnd }.map(\.start).min() ?? driveFrames)
            if trusted < takeEnd, !repairedWhole { metadata.repairs.removeAll { $0.copy == .drive } }
            // The tail Stop recorded (it reaches the Take's end) is replaced below. A data Gap (a Dropout, late-join silence) that
            // runs past what is trusted is clipped to it, and one that starts past it is covered by the new tail.
            metadata.gaps = metadata.gaps.compactMap { gap in
                guard gap.copy == .drive, !repairedWhole else { return gap }
                if gap.end >= takeEnd || gap.start >= trusted { return nil }
                return gap.end > trusted ? .init(copy: .drive, start: gap.start, end: trusted) : gap
            }
            if trusted < takeEnd, !repairedWhole { metadata.gaps.append(.init(copy: .drive, start: trusted, end: takeEnd)) }
            let remaining = marked.filter { $0 != .drive }
            metadata.abandonedCopies = remaining.isEmpty ? nil : remaining
            if hasDevice { try? metadata.write(to: deviceTake) }
            try? metadata.write(to: driveTake)
            let seconds = metadata.sampleRate > 0 ? Double(takeEnd) / Double(metadata.sampleRate) : 0
            found.append(.init(
                metadata: metadata, folders: hasDevice ? [.device: deviceTake, .drive: driveTake] : [.drive: driveTake],
                endedAt: metadata.startedAt.addingTimeInterval(seconds)))
        }
        return found
    }
}

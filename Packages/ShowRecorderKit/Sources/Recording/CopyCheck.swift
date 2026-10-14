import BroadcastWave
import CryptoKit
import Destinations
import Foundation

/// Checks that the Drive Copy of a Show is whole, so the Device Copy can be deleted without losing anything:
/// every Take and every channel the Device has is on the Drive, the Drive's Take has no Gaps left, and each
/// Stem has the same length and the same audio (a SHA-256 of its samples) in both Copies.
///
/// It reads every Stem, so run it off the main thread.
public enum CopyCheck {
    public enum Result: Equatable, Sendable {
        case passed
        /// Why the Drive Copy can't be trusted, one line per problem.
        case failed([String])
    }

    public static func verify(show: String, device: URL, drive: URL) -> Result {
        let deviceShow = device.appending(path: show, directoryHint: .isDirectory)
        let driveShow = drive.appending(path: show, directoryHint: .isDirectory)
        guard ShowDeleter.isRealFolder(driveShow) else { return .failed(["The Drive doesn't have this Show."]) }
        var problems: [String] = []

        let deviceTakes = ShowList.takeMetadata(in: deviceShow).sorted { $0.take.take < $1.take.take }
        if deviceTakes.isEmpty { return .failed(["The Device copy has no Takes to compare."]) }
        for (deviceFolder, deviceTake) in deviceTakes {
            let driveFolder = driveShow.appending(path: deviceFolder.lastPathComponent, directoryHint: .isDirectory)
            problems += self.problems(deviceFolder: deviceFolder, deviceTake: deviceTake, driveFolder: driveFolder)
        }
        return problems.isEmpty ? .passed : .failed(problems)
    }

    /// Checks one Take's Drive Copy against its Device Copy, as `verify` does for each Take of a Show (#630).
    /// - Parameter checksDriveOutcome: false to compare the audio only, before a move has recorded its Repair.
    public static func verifyTake(device: URL, drive: URL, checksDriveOutcome: Bool = true) -> Result {
        guard let deviceTake = try? TakeMetadata.read(fromTakeFolder: device) else {
            return .failed(["\(device.lastPathComponent) can't be read on the Device."])
        }
        if let problem = pairProblem(deviceTake, device: device, drive: drive) { return .failed([problem]) }
        let problems = problems(deviceFolder: device, deviceTake: deviceTake, driveFolder: drive, checksDriveOutcome: checksDriveOutcome)
        return problems.isEmpty ? .passed : .failed(problems)
    }

    /// `pairProblem` for the Device's Take at `device`, read from its Take.json (#630).
    static func takePairProblem(device: URL, drive: URL) -> String? {
        guard let deviceTake = try? TakeMetadata.read(fromTakeFolder: device) else { return "\(device.lastPathComponent) can't be read on the Device." }
        return pairProblem(deviceTake, device: device, drive: drive)
    }

    /// Why two Take folders can't be compared at all, if they can't: a Take with no channels (nothing to compare would
    /// pass), a folder that is a link or missing, the same folder twice, or two different recordings.
    private static func pairProblem(_ deviceTake: TakeMetadata, device: URL, drive: URL) -> String? {
        let name = TakeMetadata.name(take: deviceTake.take)
        if deviceTake.usbChannels.isEmpty { return "\(name) has no channels." }
        guard ShowDeleter.isRealFolder(device) else { return "\(name) isn't a folder of its own on the Device." }
        guard FileManager.default.fileExists(atPath: drive.path) else { return "\(name) is missing on the Drive." }
        guard ShowDeleter.isRealFolder(drive) else { return "\(name) isn't a folder of its own on the Drive." }
        if sameItem(device, drive) { return "\(name)'s Device and Drive Copies are the same folder." }
        guard let driveTake = try? TakeMetadata.read(fromTakeFolder: drive) else { return "\(name) is missing on the Drive." }
        if driveTake.take != deviceTake.take || driveTake.startedAt != deviceTake.startedAt { return "\(name) on the Drive is another recording." }
        if driveTake.sampleRate != deviceTake.sampleRate { return "\(name) has a different sample rate on the Drive." }
        return nil
    }

    /// Whether two paths are one item on disk, however they're spelled.
    private static func sameItem(_ a: URL, _ b: URL) -> Bool {
        if a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path { return true }
        let ids = [a, b].map { try? $0.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier }
        guard let first = ids[0], let second = ids[1] else { return false }
        return first.isEqual(second)
    }

    /// One Take's problems. A Device Take with stand-ins always has one ("still has audio only on the Device"): its
    /// stand-ins are checked against the Drive by `verifyStandIn`, which is what moving them relies on (#630).
    private static func problems(deviceFolder: URL, deviceTake: TakeMetadata, driveFolder: URL, checksDriveOutcome: Bool = true) -> [String] {
        var problems: [String] = []
        let name = TakeMetadata.name(take: deviceTake.take)
        guard let driveTake = try? TakeMetadata.read(fromTakeFolder: driveFolder) else {
            return ["\(name) is missing on the Drive."]
        }
        let outcome = driveTake.outcome(ofCopy: .drive)
        if checksDriveOutcome, outcome == .hasGaps || outcome == .repairFailed {
            problems.append("\(name) on the \(DestinationKind.drive.name) still \(CopyOutcome.hasGaps.word).")
        }
        // Audio the Device stood in for isn't on the Drive yet, whatever the Drive's Take says (#627).
        let standIns = deviceTake.standIns.flatMap { $0.isEmpty ? nil : $0 }
        if standIns != nil { problems.append("\(name) still has audio only on the \(DestinationKind.device.name).") }
        for channel in deviceTake.usbChannels {
            guard let match = driveTake.usbChannels.first(where: { $0.usbChannel == channel.usbChannel }) else {
                problems.append("\(name), channel \(channel.usbChannel) is missing on the Drive.")
                continue
            }
            // A stand-in kept on the Device holds only a stretch of the Take, in its own folder: it can only be
            // read, not compared with the Drive's Stem (#627).
            if let standIns {
                if standIns.contains(where: { (try? StemFile.inspect(deviceFolder.appending(path: $0.folderName).appending(path: channel.stemFile))) == nil }) {
                    problems.append("\(name), channel \(channel.usbChannel) can't be read on the Device.")
                }
                continue
            }
            let deviceStem = deviceFolder.appending(path: channel.stemFile)
            let driveStem = driveFolder.appending(path: match.stemFile)
            guard let a = (try? StemFile.inspect(deviceStem))?.audioRegion else {
                problems.append("\(name), channel \(channel.usbChannel) can't be read on the Device.")
                continue
            }
            guard let b = (try? StemFile.inspect(driveStem))?.audioRegion else {
                problems.append("\(name), channel \(channel.usbChannel) can't be read on the Drive.")
                continue
            }
            if a.length != b.length {
                problems.append("\(name), channel \(channel.usbChannel) is a different length on the Drive.")
            } else if hash(deviceStem, a) != hash(driveStem, b) {
                problems.append("\(name), channel \(channel.usbChannel) has different audio on the Drive.")
            }
        }
        return problems
    }

    /// Drive only (#630): whether the Drive holds each stand-in of the Device's Take byte for byte: for every stand-in
    /// and channel, the Drive Stem's samples over `start..<end` are the whole stand-in Stem. Moving a kept stand-in
    /// checks it with this, not with `verifyTake`, which fails for any Take that still has a stand-in.
    public static func verifyStandIn(deviceTake: URL, driveTake: URL) -> Result {
        if let problem = standInProblem(deviceTake: deviceTake, driveTake: driveTake) { return .failed([problem]) }
        guard let take = try? TakeMetadata.read(fromTakeFolder: deviceTake), let standIns = take.standIns,
              let driveMetadata = try? TakeMetadata.read(fromTakeFolder: driveTake) else {
            return .failed(["\(deviceTake.lastPathComponent) can't be read."])
        }
        let name = TakeMetadata.name(take: take.take)
        let size = UInt64(StemWriter.bytesPerSample)
        var problems: [String] = []
        for channel in take.usbChannels {
            guard let match = driveMetadata.usbChannels.first(where: { $0.usbChannel == channel.usbChannel }) else {
                problems.append("\(name), channel \(channel.usbChannel) of the stand-in is missing on the Drive.")
                continue
            }
            let driveStem = driveTake.appending(path: match.stemFile)
            let drive = (try? StemFile.inspect(driveStem))?.audioRegion
            for standIn in standIns {
                let label = "\(name), channel \(channel.usbChannel) of the stand-in at \(clock(frame: standIn.start, sampleRate: take.sampleRate))"
                let stem = deviceTake.appending(path: standIn.folderName).appending(path: channel.stemFile)
                // A zero-length stand-in passes only when its Stems are empty: none of the Take is in it.
                let length = UInt64(standIn.end - standIn.start) * size
                let driveStart = UInt64(standIn.start) * size
                guard let a = (try? StemFile.inspect(stem))?.audioRegion, a.length == length else {
                    problems.append("\(label) can't be read whole on the Device.")
                    continue
                }
                guard let b = drive, driveStart + length <= b.length else {
                    problems.append("\(label) isn't all on the Drive.")
                    continue
                }
                if !sameBytes(stem, at: a.offset, driveStem, at: b.offset + driveStart, length: length) {
                    problems.append("\(label) has different audio on the Drive.")
                }
            }
        }
        return problems.isEmpty ? .passed : .failed(problems)
    }

    /// Why the Device's Take at `deviceTake` and the Drive's at `driveTake` can't be compared as a stand-in and its
    /// Drive Take at all, if they can't: either can't be read, the Device's lists no stand-in or one that can't be, the
    /// two aren't the same recording in folders of their own, or a stand-in isn't a folder of its own holding only the
    /// Stems the Take lists. Moving a stand-in checks this before it writes anything to the Drive (#630).
    static func standInProblem(deviceTake: URL, driveTake: URL) -> String? {
        guard let take = try? TakeMetadata.read(fromTakeFolder: deviceTake) else { return "\(deviceTake.lastPathComponent) can't be read on the Device." }
        let name = TakeMetadata.name(take: take.take)
        guard let standIns = take.standIns, !standIns.isEmpty else { return "\(name) has no stand-in on the Device." }
        guard standIns.allSatisfy({ $0.start >= 0 && $0.end >= $0.start }) else { return "\(name)'s Take.json lists a stand-in that can't be." }
        if let problem = pairProblem(take, device: deviceTake, drive: driveTake) { return problem }
        guard (try? TakeMetadata.read(fromTakeFolder: driveTake)) != nil else { return "\(name) is missing on the Drive." }
        let listed = Set(take.usbChannels.map(\.stemFile))
        for standIn in standIns {
            let folder = deviceTake.appending(path: standIn.folderName)
            guard ShowDeleter.isRealFolder(folder) else { return "\(name)'s stand-in isn't a folder of its own on the Device." }
            // The Finder's .DS_Store on macOS is no file of the Take's.
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
                  Set(files).subtracting([".DS_Store"]).isSubset(of: listed) else {
                return "\(name)'s stand-in has files the Take doesn't list."
            }
        }
        return nil
    }

    /// "m:ss" of a Take frame.
    private static func clock(frame: Int, sampleRate: Int) -> String {
        let seconds = sampleRate > 0 ? frame / sampleRate : 0
        return "\(seconds / 60):" + (seconds % 60 < 10 ? "0" : "") + "\(seconds % 60)"
    }

    /// Whether `length` bytes of `a` from `offsetA` equal those of `b` from `offsetB`, read in pieces.
    private static func sameBytes(_ a: URL, at offsetA: UInt64, _ b: URL, at offsetB: UInt64, length: UInt64) -> Bool {
        guard let ha = try? FileHandle(forReadingFrom: a), let hb = try? FileHandle(forReadingFrom: b) else { return false }
        defer {
            try? ha.close()
            try? hb.close()
        }
        do {
            try ha.seek(toOffset: offsetA)
            try hb.seek(toOffset: offsetB)
            var remaining = length
            while remaining > 0 {
                let count = Int(min(remaining, 4 << 20))
                guard let x = try ha.read(upToCount: count), let y = try hb.read(upToCount: count), x.count == count, x == y else { return false }
                remaining -= UInt64(count)
            }
            return true
        } catch { return false }
    }

    /// A SHA-256 of the samples in `region` of the file, read in pieces.
    private static func hash(_ url: URL, _ region: (offset: UInt64, length: UInt64)) -> SHA256.Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = region.length
        do {
            try handle.seek(toOffset: region.offset)
            while remaining > 0, let chunk = try handle.read(upToCount: Int(min(remaining, 4 << 20))), !chunk.isEmpty {
                hasher.update(data: chunk)
                remaining -= UInt64(chunk.count)
            }
        } catch { return nil }
        return remaining == 0 ? hasher.finalize() : nil
    }
}

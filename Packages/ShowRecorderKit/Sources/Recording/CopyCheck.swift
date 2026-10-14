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
            let name = TakeMetadata.name(take: deviceTake.take)
            let driveFolder = driveShow.appending(path: deviceFolder.lastPathComponent, directoryHint: .isDirectory)
            guard let driveTake = try? TakeMetadata.read(fromTakeFolder: driveFolder) else {
                problems.append("\(name) is missing on the Drive.")
                continue
            }
            let outcome = driveTake.outcome(ofCopy: .drive)
            if outcome == .hasGaps || outcome == .repairFailed {
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
        }
        return problems.isEmpty ? .passed : .failed(problems)
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

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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let deviceTakes = ShowList.takeMetadata(in: deviceShow).sorted { $0.take.take < $1.take.take }
        if deviceTakes.isEmpty { return .failed(["The Device copy has no Takes to compare."]) }
        for (deviceFolder, deviceTake) in deviceTakes {
            let name = String(format: "Take %02d", deviceTake.take)
            let driveFolder = driveShow.appending(path: deviceFolder.lastPathComponent, directoryHint: .isDirectory)
            guard let data = try? Data(contentsOf: driveFolder.appending(path: TakeMetadata.fileName)),
                  let driveTake = try? decoder.decode(TakeMetadata.self, from: data) else {
                problems.append("\(name) is missing on the Drive.")
                continue
            }
            let outcome = driveTake.outcome(ofCopy: .drive)
            if outcome == .hasGaps || outcome == .repairFailed {
                problems.append("\(name) on the Drive still has Gaps.")
            }
            for channel in deviceTake.usbChannels {
                guard let match = driveTake.usbChannels.first(where: { $0.usbChannel == channel.usbChannel }) else {
                    problems.append("\(name), channel \(channel.usbChannel) is missing on the Drive.")
                    continue
                }
                let deviceStem = deviceFolder.appending(path: channel.stemFile)
                let driveStem = driveFolder.appending(path: match.stemFile)
                guard let a = StemLength.audioRegion(at: deviceStem) else {
                    problems.append("\(name), channel \(channel.usbChannel) can't be read on the Device.")
                    continue
                }
                guard let b = StemLength.audioRegion(at: driveStem) else {
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

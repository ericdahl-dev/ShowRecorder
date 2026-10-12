import BroadcastWave
import Destinations
import Foundation
import TakeFile

/// Finishes a Take cut off by a crash or a kill, at the next launch (#319). A Take that finished set the Show's
/// `lastTakeEndedAt`; a last Take that started after it (or with none) was cut off.
///
/// - Each Stem's header is rewritten to cover the whole samples on disk: a header is committed every 2 s, so up to
///   2 s of audio that reached the disk would otherwise be hidden. A torn last sample is cut off and the pad byte
///   added. A Stem whose header isn't the size this writer makes is left alone rather than risk its audio.
/// - A Copy shorter than the longest gets a Gap in `Take.json`, which Repair then fills.
/// - Levels aren't worked out (that would read every sample at launch); Markers are already in the Stems up to the
///   last header commit.
enum CutOffTake {
    struct Found {
        var metadata: TakeMetadata
        var folders: [URL]
        /// When the Take ended, from its longest Copy.
        var endedAt: Date
    }

    /// The last Take of the Show at `deviceShow` (and its Drive Copy at `driveShow`, when reachable), finished if it
    /// was cut off; nil when the Show's last Take finished normally or there is none.
    static func finish(deviceShow: URL, driveShow: URL?, lastTakeEndedAt: Date?) -> Found? {
        let fm = FileManager.default
        let numbers = ((try? fm.contentsOfDirectory(atPath: deviceShow.path)) ?? [])
            .compactMap { $0.hasPrefix("Take ") ? Int($0.dropFirst(5)) : nil }
        guard let last = numbers.max() else { return nil }
        let name = TakeMetadata.name(take: last)
        let deviceTake = deviceShow.appending(path: name, directoryHint: .isDirectory)
        guard var metadata = try? TakeMetadata.read(fromTakeFolder: deviceTake) else { return nil }
        if let lastTakeEndedAt, metadata.startedAt <= lastTakeEndedAt { return nil }

        var copies: [(kind: DestinationKind, folder: URL)] = [(.device, deviceTake)]
        if let driveTake = driveShow?.appending(path: name, directoryHint: .isDirectory), fm.fileExists(atPath: driveTake.path) {
            copies.append((.drive, driveTake))
        }
        let info = StemWriter.Info(
            sampleRate: metadata.sampleRate, description: "", originator: "ShowRecorder",
            timeReference: metadata.timeReference, originationDate: metadata.startedAt)
        var lengths: [DestinationKind: UInt64] = [:]
        for copy in copies {
            lengths[copy.kind] = metadata.usbChannels
                .compactMap { finishStem(at: copy.folder.appending(path: $0.stemFile), info: info) }
                .max() ?? 0
        }
        let coverage = CopyCoverage(stemLengths: lengths.mapValues { Int($0) })
        let longest = UInt64(coverage.end)
        for gap in coverage.gaps(takeEnd: coverage.end) where !metadata.gaps.contains(gap) {
            metadata.gaps.append(gap)
        }
        for copy in copies { try? metadata.write(to: copy.folder) }
        let seconds = metadata.sampleRate > 0 ? Double(longest) / Double(metadata.sampleRate) : 0
        return Found(metadata: metadata, folders: copies.map(\.folder), endedAt: metadata.startedAt.addingTimeInterval(seconds))
    }

    /// Rewrites the Stem's header to cover its whole samples on disk, unless it already does. Returns its frames,
    /// or nil when it isn't there or isn't a Stem this writer made.
    static func finishStem(at url: URL, info: StemWriter.Info) -> UInt64? {
        guard let stem = try? StemFile.inspect(url) else { return nil }
        // Resuming truncates at this writer's header size plus the frames: a different header would lose audio.
        guard stem.dataStart == UInt64(StemWriter.dataStart) else { return stem.frameCount }
        let onDisk = stem.framesOnDisk
        let dataBytes = onDisk * UInt64(StemWriter.bytesPerSample)
        let finished = stem.declaredBytes == dataBytes && stem.bytesOnDisk == dataBytes + dataBytes % 2
        guard !finished else { return onDisk }
        guard let writer = try? StemWriter.open(url: url, info: info, resumingAt: onDisk), (try? writer.finalize()) != nil else {
            return stem.frameCount
        }
        return onDisk
    }
}

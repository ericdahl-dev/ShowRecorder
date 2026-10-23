import BroadcastWave
import Destinations
import Foundation

/// Names USB Channels by hand in a Take that has been recorded, working from the files: each named
/// channel's Stem is renamed ("07 Lead Vocal.wav"), its bext description is updated, and `Take.json`
/// carries the name, in every Copy it can reach. Then the Show's report and project are regenerated.
///
/// The audio is not touched. A Copy that can't be reached or read is left as it is and named in the
/// outcome; the others are still renamed.
public enum ChannelRenamer {
    public struct Outcome: Equatable, Sendable {
        /// `.renamed` if at least one Copy was.
        public var result: MarkerRename
        public var renamed: [DestinationKind]
        public var failed: [MarkerRenamer.Failure]
    }

    /// - Parameters:
    ///   - names: the new name for each USB Channel (1-based) to rename.
    ///   - lateChannels: the channels whose name is the Mixer's, which only arrived during the Take.
    ///   - copies: each Copy's folder for this Take (`…/Show/Take 01`).
    ///   - allowsProExtras: whether the Show report and Reaper project may be written (`License.allowsProExtras`);
    ///     ones already there are rewritten either way (#438).
    public static func rename(names: [Int: String], lateChannels: Set<Int> = [], in copies: [DestinationKind: URL], allowsProExtras: Bool) -> Outcome {
        let names = names.compactMapValues { name -> String? in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !names.isEmpty else { return Outcome(result: .emptyName, renamed: [], failed: []) }

        var renamed: [DestinationKind] = []
        var failed: [MarkerRenamer.Failure] = []
        for (kind, folder) in copies.sorted(by: { $0.key.index < $1.key.index }) {
            do {
                try rename(names: names, lateChannels: lateChannels, in: folder, copy: kind)
                renamed.append(kind)
            } catch {
                failed.append(.init(copy: kind, reason: String(describing: error)))
            }
        }
        for kind in renamed {
            Show.refreshExtras(showFolder: copies[kind]!.deletingLastPathComponent(), allowed: allowsProExtras)
        }
        return Outcome(result: renamed.isEmpty ? .noCopyUpdated : .renamed, renamed: renamed, failed: failed)
    }

    private static func rename(names: [Int: String], lateChannels: Set<Int>, in folder: URL, copy: DestinationKind) throws {
        var take = try TakeMetadata.read(fromTakeFolder: folder)
        let fm = FileManager.default
        // A stand-in kept on the Device has its Stems in its own folder (#622), never reached through a link (#627).
        let standIns = copy == .device ? take.standIns.flatMap { $0.isEmpty ? nil : $0 } : nil
        let stemFolders = standIns?.map { folder.appending(path: $0.folderName, directoryHint: .isDirectory) }
        if let link = stemFolders?.first(where: { !ShowDeleter.isRealFolder($0) }) {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: link.path])
        }
        for index in take.usbChannels.indices {
            let channel = take.usbChannels[index]
            guard let name = names[channel.usbChannel], name != channel.name else { continue }
            let file = StemFileName.make(usbChannel: channel.usbChannel, sourceName: name)
            for stemFolder in stemFolders ?? [folder] {
                let old = stemFolder.appending(path: channel.stemFile), new = stemFolder.appending(path: file)
                if file != channel.stemFile, fm.fileExists(atPath: new.path) {
                    throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: new.path])
                }
                // Before it is moved: a Stem another program saved is refused, and left under its name (#881).
                let stem = try StemWriter.reopen(url: old)
                try stem.setDescription(name)
                try stem.finalize()
                if file != channel.stemFile { try fm.moveItem(at: old, to: new) }
            }
            take.usbChannels[index].stemFile = file
            take.usbChannels[index].name = name
            take.usbChannels[index].hasMixerName = lateChannels.contains(channel.usbChannel)
            take.usbChannels[index].nameArrivedLate = lateChannels.contains(channel.usbChannel) ? true : nil
        }
        try take.write(to: folder)
    }
}

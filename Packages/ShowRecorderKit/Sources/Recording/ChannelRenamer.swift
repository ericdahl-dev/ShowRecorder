import BroadcastWave
import Destinations
import Foundation
import ShowReport

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
    ///   - copies: each Copy's folder for this Take (`…/Show/Take 01`).
    public static func rename(names: [Int: String], in copies: [DestinationKind: URL]) -> Outcome {
        let names = names.compactMapValues { name -> String? in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !names.isEmpty else { return Outcome(result: .emptyName, renamed: [], failed: []) }

        var renamed: [DestinationKind] = []
        var failed: [MarkerRenamer.Failure] = []
        for (kind, folder) in copies.sorted(by: { $0.key.index < $1.key.index }) {
            do {
                try rename(names: names, in: folder)
                renamed.append(kind)
            } catch {
                failed.append(.init(copy: kind, reason: String(describing: error)))
            }
        }
        for kind in renamed {
            let showFolder = copies[kind]!.deletingLastPathComponent()
            try? ShowReport.write(showFolder: showFolder)
            try? Show(name: showFolder.lastPathComponent, folder: showFolder, takeCount: 0).writeProjects()
        }
        return Outcome(result: renamed.isEmpty ? .noCopyUpdated : .renamed, renamed: renamed, failed: failed)
    }

    private static func rename(names: [Int: String], in folder: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var take = try decoder.decode(TakeMetadata.self, from: Data(contentsOf: folder.appending(path: TakeMetadata.fileName)))
        let fm = FileManager.default
        for index in take.usbChannels.indices {
            let channel = take.usbChannels[index]
            guard let name = names[channel.usbChannel], name != channel.name else { continue }
            let file = StemFileName.make(usbChannel: channel.usbChannel, sourceName: name)
            let old = folder.appending(path: channel.stemFile), new = folder.appending(path: file)
            if file != channel.stemFile {
                guard !fm.fileExists(atPath: new.path) else { throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: new.path]) }
                try fm.moveItem(at: old, to: new)
            }
            let stem = try StemWriter.reopen(url: new)
            try stem.setDescription(name)
            try stem.finalize()
            take.usbChannels[index].stemFile = file
            take.usbChannels[index].name = name
            take.usbChannels[index].hasMixerName = false
        }
        try take.write(to: folder)
    }
}

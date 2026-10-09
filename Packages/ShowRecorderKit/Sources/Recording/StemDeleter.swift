import Destinations
import Foundation
import ShowReport

/// Deletes one USB Channel's file from a Take in the Copies the operator chose: the Stem goes, its entry
/// leaves that Copy's `Take.json`, and the report and project are regenerated there. The other Copy, if not
/// chosen, keeps the channel. Permanent.
public enum StemDeleter {
    public static func delete(
        channel: Int, inTake take: Int, ofShow show: String, from copies: Set<DestinationKind>, device: URL, drive: URL?, openShow: String?
    ) -> ShowDeleter.Outcome {
        let kinds = copies.sorted { $0.index < $1.index }
        func refuse(_ reason: String) -> ShowDeleter.Outcome { .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: reason) }) }
        guard ShowDeleter.isPlainName(show), take > 0, channel > 0 else { return refuse("That isn't a channel of a Take.") }
        if show == openShow { return refuse("This Show is open. End it first.") }

        var deleted: [DestinationKind] = []
        var failed: [ShowDeleter.Failure] = []
        for kind in kinds {
            guard let parent = kind == .device ? device : drive else {
                failed.append(.init(copy: kind, reason: "The Drive isn't available."))
                continue
            }
            let showFolder = parent.appending(path: show, directoryHint: .isDirectory)
            let takeFolder = showFolder.appending(path: String(format: "Take %02d", take), directoryHint: .isDirectory)
            do {
                try delete(channel: channel, in: takeFolder, showFolder: showFolder)
                deleted.append(kind)
            } catch let error as DeleteError {
                failed.append(.init(copy: kind, reason: error.description))
            } catch {
                failed.append(.init(copy: kind, reason: error.localizedDescription))
            }
        }
        return .init(deleted: deleted, failed: failed)
    }

    private enum DeleteError: Error, CustomStringConvertible {
        case noSuchChannel
        var description: String { "There is no such channel in this Copy's Take." }
    }

    private static func delete(channel: Int, in takeFolder: URL, showFolder: URL) throws {
        guard ShowDeleter.isRealFolder(showFolder), ShowDeleter.isRealFolder(takeFolder) else { throw DeleteError.noSuchChannel }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var take = try decoder.decode(TakeMetadata.self, from: Data(contentsOf: takeFolder.appending(path: TakeMetadata.fileName)))
        guard let index = take.usbChannels.firstIndex(where: { $0.usbChannel == channel }) else { throw DeleteError.noSuchChannel }
        let file = take.usbChannels[index].stemFile
        guard ShowDeleter.isPlainName(file), file.hasSuffix(".wav") else { throw DeleteError.noSuchChannel }
        let stem = takeFolder.appending(path: file)
        // The file may already be gone; it is still taken out of Take.json.
        if FileManager.default.fileExists(atPath: stem.path) { try FileManager.default.removeItem(at: stem) }
        take.usbChannels.remove(at: index)
        try take.write(to: takeFolder)
        try? ShowReport.write(showFolder: showFolder)
        try? Show(name: showFolder.lastPathComponent, folder: showFolder, takeCount: 0).writeProjects()
    }
}

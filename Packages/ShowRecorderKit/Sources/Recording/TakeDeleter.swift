import Destinations
import Foundation
import ShowReport

/// Deletes one Take's folder from the Copies the operator chose, then regenerates the Show's report and
/// project there. Permanent. The other Takes keep their numbers.
public enum TakeDeleter {
    public static func delete(
        take: Int, ofShow show: String, from copies: Set<DestinationKind>, device: URL, drive: URL?, openShow: String?
    ) -> ShowDeleter.Outcome {
        let kinds = copies.sorted { $0.index < $1.index }
        func refuse(_ reason: String) -> ShowDeleter.Outcome { .init(deleted: [], failed: kinds.map { .init(copy: $0, reason: reason) }) }
        guard ShowDeleter.isPlainName(show), take > 0 else { return refuse("That isn't a Take of a Show.") }
        if show == openShow { return refuse("This Show is open. End it first.") }

        var deleted: [DestinationKind] = []
        var failed: [ShowDeleter.Failure] = []
        for kind in kinds {
            guard let parent = kind == .device ? device : drive else {
                failed.append(.init(copy: kind, reason: "The Drive isn't available."))
                continue
            }
            let showFolder = parent.appending(path: show, directoryHint: .isDirectory)
            let folder = showFolder.appending(path: String(format: "Take %02d", take), directoryHint: .isDirectory)
            guard ShowDeleter.isRealFolder(showFolder), ShowDeleter.isRealFolder(folder),
                  FileManager.default.fileExists(atPath: folder.appending(path: TakeMetadata.fileName).path) else {
                failed.append(.init(copy: kind, reason: "There is no such Take in this Copy."))
                continue
            }
            do {
                try FileManager.default.removeItem(at: folder)
                deleted.append(kind)
                try? ShowReport.write(showFolder: showFolder)
                try? Show(name: show, folder: showFolder, takeCount: 0).writeProjects()
            } catch {
                failed.append(.init(copy: kind, reason: error.localizedDescription))
            }
        }
        return .init(deleted: deleted, failed: failed)
    }
}

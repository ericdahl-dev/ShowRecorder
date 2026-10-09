import Destinations
import Foundation

/// Deletes a whole Show's folder from the Copies the operator chose. Permanent: there is no Trash.
///
/// It only removes the one folder named, directly inside the Device's or the Drive's Shows folder, and only
/// in the Copies asked for.
public enum ShowDeleter {
    public struct Failure: Equatable, Sendable {
        public var copy: DestinationKind
        public var reason: String
    }

    public struct Outcome: Equatable, Sendable {
        public var deleted: [DestinationKind]
        public var failed: [Failure]
    }

    /// - Parameters:
    ///   - copies: which Copies to delete from.
    ///   - drive: the Drive's Shows folder, or nil when the Drive isn't there.
    ///   - openShow: the Show being recorded into, which can't be deleted.
    public static func delete(show: String, from copies: Set<DestinationKind>, device: URL, drive: URL?, openShow: String?) -> Outcome {
        let kinds = copies.sorted { $0.index < $1.index }
        func refuse(_ reason: String) -> Outcome { Outcome(deleted: [], failed: kinds.map { Failure(copy: $0, reason: reason) }) }
        guard isPlainName(show) else { return refuse("That isn't a Show folder name.") }
        if show == openShow { return refuse("This Show is open. End it first.") }

        var deleted: [DestinationKind] = []
        var failed: [Failure] = []
        for kind in kinds {
            guard let parent = kind == .device ? device : drive else {
                failed.append(Failure(copy: kind, reason: "The Drive isn't available."))
                continue
            }
            let folder = parent.appending(path: show, directoryHint: .isDirectory)
            guard isShowFolder(folder) else {
                failed.append(Failure(copy: kind, reason: "There is no such Show in this Copy."))
                continue
            }
            do {
                try FileManager.default.removeItem(at: folder)
                deleted.append(kind)
            } catch {
                failed.append(Failure(copy: kind, reason: error.localizedDescription))
            }
        }
        return Outcome(deleted: deleted, failed: failed)
    }

    /// Whether `typed` is exactly the Show's name, which is what confirms a delete.
    public static func confirms(typed: String, for show: String) -> Bool {
        !show.isEmpty && typed == show
    }

    /// One path component that isn't hidden, so it can't climb out of the Shows folder or name a folder inside a Show.
    private static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    /// A real folder (not a link) that is a Show: it has a `Show.json` or at least one "Take NN" folder.
    private static func isShowFolder(_ folder: URL) -> Bool {
        let fm = FileManager.default
        guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return false }
        if fm.fileExists(atPath: folder.appending(path: ShowFile.fileName).path) { return true }
        return ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).contains { $0.hasPrefix("Take ") }
    }
}

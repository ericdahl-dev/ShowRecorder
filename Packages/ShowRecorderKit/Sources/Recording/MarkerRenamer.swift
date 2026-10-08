import BroadcastWave
import Destinations
import Foundation
import ShowReport

/// Renames a Marker in a Take that has already been recorded, working from the files: `Take.json` and the
/// cue label in every Stem, in every Copy it can reach. Then it regenerates the Show's report and project
/// so they show the new name.
///
/// A Marker is identified by its index among the operator's Markers, as for `Recorder.renameMarker`.
/// A Copy that can't be reached or read is left as it is and named in the outcome; the others are still
/// renamed, so the Copies can disagree until the Marker is renamed again with every Copy there.
public enum MarkerRenamer {
    public struct Failure: Equatable, Sendable {
        public var copy: DestinationKind
        public var reason: String
    }

    public struct Outcome: Equatable, Sendable {
        /// `.renamed` if at least one Copy was.
        public var result: MarkerRename
        public var renamed: [DestinationKind]
        public var failed: [Failure]
    }

    /// - Parameters:
    ///   - index: among the operator's Markers, in the order of `Take.json`.
    ///   - copies: each Copy's folder for this Take (`…/Show/Take 01`).
    public static func rename(markerAt index: Int, to name: String, in copies: [DestinationKind: URL]) -> Outcome {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return Outcome(result: .emptyName, renamed: [], failed: []) }

        var renamed: [DestinationKind] = []
        var failed: [Failure] = []
        var markerMissing = 0
        for (kind, folder) in copies.sorted(by: { $0.key.index < $1.key.index }) {
            do {
                try renameMarker(at: index, to: name, in: folder, copy: kind)
                renamed.append(kind)
            } catch RenameError.noSuchMarker {
                markerMissing += 1
                failed.append(Failure(copy: kind, reason: RenameError.noSuchMarker.description))
            } catch {
                failed.append(Failure(copy: kind, reason: String(describing: error)))
            }
        }
        for kind in renamed {
            let showFolder = copies[kind]!.deletingLastPathComponent()
            try? ShowReport.write(showFolder: showFolder)
            try? Show(name: showFolder.lastPathComponent, folder: showFolder, takeCount: 0).writeProjects()
        }
        let result: MarkerRename = !renamed.isEmpty ? .renamed : markerMissing == failed.count ? .noSuchMarker : .noCopyUpdated
        return Outcome(result: result, renamed: renamed, failed: failed)
    }

    private enum RenameError: Error, CustomStringConvertible {
        case noSuchMarker
        case stemsNotUpdated([String])

        var description: String {
            switch self {
            case .noSuchMarker: "There is no Marker at that place in this Copy."
            case .stemsNotUpdated(let names): "Couldn't update \(names.joined(separator: ", ")); the Take's other Stems and Take.json were renamed."
            }
        }
    }

    private static func renameMarker(at index: Int, to name: String, in folder: URL, copy: DestinationKind) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var take = try decoder.decode(TakeMetadata.self, from: Data(contentsOf: folder.appending(path: TakeMetadata.fileName)))
        let positions = take.markers.indices.filter { take.markers[$0].origin == .operator }
        guard positions.indices.contains(index) else { throw RenameError.noSuchMarker }
        take.markers[positions[index]].name = name
        try take.write(to: folder)

        // The cue points a Copy's Stems carry: the operator's Markers and a Dropout cue where this Copy lost audio.
        let cues = (take.markers.filter { $0.origin == .operator }.map { StemMarker(position: UInt32(clamping: $0.position), label: $0.name) }
            + take.dropouts.filter { $0.copy == copy }.map { StemMarker(position: UInt32(clamping: $0.start), label: "Dropout") })
            .sorted { $0.position < $1.position }
        // Every Stem is tried, so one bad file doesn't leave the others with the old name.
        var unreadable: [String] = []
        for channel in take.usbChannels {
            do {
                let stem = try StemWriter.reopen(url: folder.appending(path: channel.stemFile))
                try stem.setMarkers(cues)
                try stem.finalize()
            } catch {
                unreadable.append(channel.stemFile)
            }
        }
        if !unreadable.isEmpty { throw RenameError.stemsNotUpdated(unreadable) }
    }
}

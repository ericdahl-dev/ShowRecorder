import Destinations
import Foundation

/// One Take of a Show on the detail screen.
public struct TakeDetail: Equatable, Sendable, Identifiable {
    public var id: Int { number }
    public var number: Int
    public var folderName: String
    public var markers: [MarkerDetail]
    /// The channels this Copy of the Take has a file for.
    public var channels: [ChannelDetail]
}

/// One channel's file in a Take.
public struct ChannelDetail: Equatable, Sendable {
    public var number: Int
    public var name: String
}

/// One Marker in a Take, in the order of `Take.json`.
public struct MarkerDetail: Equatable, Sendable {
    public var name: String
    /// Seconds from the start of the Take's audio.
    public var seconds: Double
    /// Its position among the operator's Markers, which is what a rename needs; nil for a Dropout Marker,
    /// which can't be renamed.
    public var operatorIndex: Int?
}

/// Reads a Show's Takes and their Markers from the files.
public enum ShowDetail {
    public static func read(showFolder: URL) -> [TakeDetail] {
        ShowList.takeMetadata(in: showFolder)
            .sorted { $0.take.take < $1.take.take }
            .map { folder, take in
                var operatorCount = 0
                let markers = take.markers.map { marker -> MarkerDetail in
                    var index: Int?
                    if marker.origin == .operator { index = operatorCount; operatorCount += 1 }
                    return MarkerDetail(name: marker.name, seconds: Double(marker.position) / Double(max(take.sampleRate, 1)), operatorIndex: index)
                }
                return TakeDetail(
                    number: take.take, folderName: folder.lastPathComponent, markers: markers,
                    channels: take.usbChannels.map { ChannelDetail(number: $0.usbChannel, name: $0.name) })
            }
    }

    /// Renames the operator Marker at `index` (see `MarkerDetail.operatorIndex`) in Take `take` of the
    /// Show named `show`, in the Device Copy and, when `drive` is given and has the Show, the Drive Copy.
    /// This is the after-the-Take rename: `Take.json` and every Stem's cue label, then the report and project.
    public static func renameMarker(
        at index: Int, to name: String, inTake take: Int, ofShow show: String, device: URL, drive: URL?
    ) -> MarkerRenamer.Outcome {
        let takeFolder = String(format: "Take %02d", take)
        var copies: [DestinationKind: URL] = [.device: device.appending(path: show).appending(path: takeFolder)]
        if let drive {
            let folder = drive.appending(path: show).appending(path: takeFolder)
            if FileManager.default.fileExists(atPath: folder.path) { copies[.drive] = folder }
        }
        return MarkerRenamer.rename(markerAt: index, to: name, in: copies)
    }
}

import Foundation
import TakeFile

/// What the record screen says while a Take runs on after the Mixer's USB routing changed (#21): the Take goes on,
/// each Stem keeps the name it started with, and a Marker marks each change.
public enum RoutingChangeNotice {
    /// `stemNames` holds each re-patched USB Channel's Stem name, as named at the Take's start.
    public static func message(for changes: [TakeMetadata.RoutingChange], stemNames: [Int: String]) -> String? {
        guard let change = changes.first else { return nil }
        guard changes.count == 1 else {
            let channels = Array(Set(changes.map(\.usbChannel))).sorted().map { String(format: "%02d", $0) }
            return "\(changes.count) re-patches during this Take (USB \(channels.joined(separator: ", "))). The Stems keep their names; Markers mark each change."
        }
        let stem = stemNames[change.usbChannel] ?? change.from
        return "USB \(String(format: "%02d", change.usbChannel)) now carries \(change.to) (was \(change.from)). Its Stem keeps the name \(stem); a Marker marks the change."
    }

    /// The Marker's name at a routing change, in `Take.json` and as the Stems' cue label: plain ASCII around the
    /// Source names, cut to the cue label limit.
    static func markerName(usbChannel: Int, from: String, to: String) -> String {
        NameLimit.cut("USB \(String(format: "%02d", usbChannel)) re-patched: \(from) to \(to)")
    }
}

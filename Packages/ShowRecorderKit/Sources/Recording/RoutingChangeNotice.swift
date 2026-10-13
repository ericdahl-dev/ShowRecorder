import TakeFile

/// What the record screen says while a Take runs on after the Mixer's USB routing changed (#21): the Take goes on,
/// each Stem keeps the name it started with, and a Marker marks each change.
public enum RoutingChangeNotice {
    public static func message(for changes: [TakeMetadata.RoutingChange]) -> String? {
        guard let change = changes.first else { return nil }
        guard changes.count == 1 else {
            return "\(changes.count) USB Channels were re-patched during this Take. Their Stems keep their names; Markers mark each change."
        }
        return "USB \(change.usbChannel) now carries \(change.to) (was \(change.from)). Its Stem keeps the name \(change.from); a Marker marks the change."
    }
}

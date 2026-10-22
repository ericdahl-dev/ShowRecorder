import BroadcastWave
import Destinations
import TakeFile

extension TakeMetadata {
    /// The cue points the Stems of `copy` carry, in order of position: the operator's Markers and the routing changes
    /// (`stemCueMarkers`), and a Dropout cue where that Copy lost audio. One list for a recording, a Repair, a stand-in move
    /// and a Marker rename, so the Copies' Stems carry the same cues whichever of them wrote last (#887). Gain and other
    /// Markers stay in `Take.json`. A Dropout is cued in the Copy that logged it; where it overlaps silence another Copy
    /// holds there (a lead-in Gap), that Copy's Stem has no cue for it. A recording cues each writer's own drops live, which
    /// can differ from this list on a partial overlap; the issue chose this list (#887).
    func stemCues(for copy: DestinationKind) -> [StemMarker] {
        (stemCueMarkers.map { StemMarker(position: UInt32(clamping: $0.position), label: $0.name) }
            + dropouts.filter { $0.copy == copy }.map { StemMarker(position: UInt32(clamping: $0.start), label: "Dropout") })
            .sorted { $0.position < $1.position }
    }
}

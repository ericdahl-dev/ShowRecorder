import BroadcastWave
import Foundation

/// Repair (#14): after a Take ends, fills each Copy's Gaps from the other Copy.
enum TakeRepair {
    struct Copy: Sendable {
        /// "device" or "drive", as in `TakeMetadata.Gap.copy`.
        var name: String
        var folder: URL
    }

    /// Repairs every Copy that has Gaps from the other Copy and returns what happened to each Gap.
    /// A Gap is repaired only if the other Copy has the samples; where both Copies are missing the
    /// same stretch it stays silence and is reported as failed.
    static func run(copies: [Copy], metadata: TakeMetadata) -> [TakeMetadata.Repair] {
        let markers = metadata.markers.map { StemMarker(position: UInt32(clamping: $0.position), label: $0.name) }
        let stems = metadata.usbChannels.map(\.stemFile)
        let length = max(
            metadata.gaps.map(\.end).max() ?? 0,
            copies.flatMap { copy in stems.map { Int(StemWriter.frameCount(of: copy.folder.appending(path: $0)) ?? 0) } }.max() ?? 0)

        var repairs: [TakeMetadata.Repair] = []
        for target in copies {
            let gaps = metadata.gaps.filter { $0.copy == target.name }
            guard !gaps.isEmpty else { continue }
            let source = copies.first { $0.name != target.name }
            let sourceGaps = metadata.gaps.filter { $0.copy != target.name }.map { $0.start..<$0.end }

            var copied = source != nil
            if let source {
                do {
                    for stem in stems {
                        try StemRepair.fill(
                            target: target.folder.appending(path: stem), from: source.folder.appending(path: stem),
                            ranges: gaps.map { $0.start..<$0.end }, length: length, markers: markers)
                    }
                } catch {
                    copied = false
                }
            }
            for gap in gaps {
                let range = gap.start..<gap.end
                let sourceHasIt = !sourceGaps.contains { $0.overlaps(range) }
                repairs.append(.init(copy: gap.copy, start: gap.start, end: gap.end, outcome: copied && sourceHasIt ? .repaired : .failed))
            }
        }
        return repairs
    }
}

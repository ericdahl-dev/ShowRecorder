import BroadcastWave
import Destinations
import Foundation

/// Repair (#14): after a Take ends, fills each Copy's Gaps from the other Copy.
enum TakeRepair {
    struct Copy: Sendable {
        var kind: DestinationKind
        var folder: URL
    }

    /// The Take's length in frames: the longest Stem in any Copy, or the end of the last Gap.
    static func length(copies: [Copy], metadata: TakeMetadata) -> Int {
        let stems = metadata.usbChannels.map(\.stemFile)
        return max(
            metadata.gaps.map(\.end).max() ?? 0,
            copies.flatMap { copy in stems.map { Int(StemWriter.frameCount(of: copy.folder.appending(path: $0)) ?? 0) } }.max() ?? 0)
    }

    /// Bytes Repair would add to `copy`'s Stems to bring them to the Take's length. Filling a Gap in the
    /// middle needs no space; only a Copy that stopped early grows.
    static func bytesToExtend(_ copy: Copy, in copies: [Copy], metadata: TakeMetadata) -> Int64 {
        let length = length(copies: copies, metadata: metadata)
        return metadata.usbChannels.reduce(into: Int64(0)) { total, channel in
            let frames = Int(StemWriter.frameCount(of: copy.folder.appending(path: channel.stemFile)) ?? 0)
            total += Int64(max(length - frames, 0)) * 3
        }
    }

    /// Repairs every Copy that has Gaps from the other Copy and returns what happened to each Gap.
    /// A Gap is repaired only if the other Copy has the samples; where both Copies are missing the
    /// same stretch it stays silence and is reported as failed. Copies named in `skip` are left alone
    /// and get no entry: they stay as they were, with their Gaps.
    static func run(copies: [Copy], metadata: TakeMetadata, skip: Set<DestinationKind> = []) -> [TakeMetadata.Repair] {
        let markers = metadata.markers.map { StemMarker(position: UInt32(clamping: $0.position), label: $0.name) }
        let stems = metadata.usbChannels.map(\.stemFile)
        let length = length(copies: copies, metadata: metadata)

        var repairs: [TakeMetadata.Repair] = []
        for target in copies where !skip.contains(target.kind) {
            let gaps = metadata.gaps.filter { $0.copy == target.kind }
            guard !gaps.isEmpty else { continue }
            let source = copies.first { $0.kind != target.kind }
            let sourceGaps = metadata.gaps.filter { $0.copy != target.kind }.map { $0.start..<$0.end }

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

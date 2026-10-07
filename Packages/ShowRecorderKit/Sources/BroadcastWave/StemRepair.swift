import Foundation

/// Repair for one Stem (#14): fills stretches of a Copy's Stem from the same Stem in the other Copy.
public enum StemRepair {
    /// Copies `ranges` (in frames) from `source` into `target`, and extends `target` to `length` frames
    /// from `source` if it ended early. Frames `source` doesn't have are written as silence. Then writes
    /// `markers` and finalizes `target`, so the two Stems end byte-identical.
    public static func fill(target: URL, from source: URL, ranges: [Range<Int>], length: Int, markers: [StemMarker]) throws {
        guard let targetFrames = StemWriter.frameCount(of: target) else { throw CocoaError(.fileReadCorruptFile) }
        let writer = try StemWriter.reopen(url: target)
        let chunk = 48_000

        for range in ranges {
            var start = range.lowerBound
            let end = min(range.upperBound, Int(targetFrames))
            while start < end {
                let part = start..<min(start + chunk, end)
                try StemWriter.readSamples(url: source, frames: part).withUnsafeBufferPointer { try writer.overwrite($0, atFrame: UInt64(part.lowerBound)) }
                start = part.upperBound
            }
        }
        var next = Int(targetFrames)
        while next < length {
            let part = next..<min(next + chunk, length)
            try StemWriter.readSamples(url: source, frames: part).withUnsafeBufferPointer { try writer.append($0) }
            next = part.upperBound
        }
        try writer.setMarkers(markers)
        try writer.finalize()
    }
}

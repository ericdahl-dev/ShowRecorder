import Foundation

/// Repair for one Stem (#14): fills stretches of a Copy's Stem from the same Stem in the other Copy.
public enum StemRepair {
    /// A fill asked to stop before it finished.
    public struct Stopped: Error {
        public init() {}
    }

    /// Copies `ranges` (in frames) from `source` into `target`, and extends `target` to `length` frames
    /// from `source` if it ended early. Frames `source` doesn't have are written as silence. Then writes
    /// `markers` and finalizes `target`, so the two Stems end byte-identical.
    /// - Parameter sourceStart: the Take frame `source`'s first frame is: 0 for a Copy, where a Drive only Take's
    ///   Device stand-in began for one (#196). Frames are always Take frames.
    /// - Parameter shouldStop: asked before each piece; when it says to stop, this throws `Stopped`, leaving `target`
    ///   with what was written so far and its header as it was.
    public static func fill(
        target: URL, from source: URL, sourceStart: Int = 0, ranges: [Range<Int>], length: Int, markers: [StemMarker],
        shouldStop: () -> Bool = { false }
    ) throws {
        func read(_ part: Range<Int>) throws -> [Float] {
            try StemWriter.readSamples(url: source, frames: (part.lowerBound - sourceStart)..<(part.upperBound - sourceStart))
        }
        let targetFrames = try StemFile.inspect(target).framesOnDisk
        let writer = try StemWriter.reopen(url: target)
        let chunk = 48_000

        for range in ranges {
            var start = range.lowerBound
            let end = min(range.upperBound, Int(targetFrames))
            while start < end {
                if shouldStop() { throw Stopped() }
                let part = start..<min(start + chunk, end)
                try read(part).withUnsafeBufferPointer { try writer.overwrite($0, atFrame: UInt64(part.lowerBound)) }
                start = part.upperBound
            }
        }
        var next = Int(targetFrames)
        while next < length {
            if shouldStop() { throw Stopped() }
            let part = next..<min(next + chunk, length)
            try read(part).withUnsafeBufferPointer { try writer.append($0) }
            next = part.upperBound
        }
        try writer.setMarkers(markers)
        try writer.finalize()
    }
}

import Foundation

/// Repair for one Stem (#14): fills stretches of a Copy's Stem from the same Stem in the other Copy.
public enum StemRepair {
    /// Copies `ranges` (in frames) from `source` into `target`, and extends `target` to `length` frames
    /// from `source` if it ended early. Frames `source` doesn't have are written as silence. Then writes
    /// `markers` and finalizes `target`, so the two Stems end byte-identical.
    public static func fill(target: URL, from source: URL, ranges: [Range<Int>], length: Int, markers: [StemMarker]) throws {
        guard let targetFrames = StemWriter.frameCount(of: target) else { throw CocoaError(.fileReadCorruptFile) }
        let info = StemWriter.Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: Date(timeIntervalSince1970: 0))
        let writer = try StemWriter.open(url: target, info: info, resumingAt: targetFrames)
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let sourceFrames = Int(StemWriter.frameCount(of: source) ?? 0)
        let chunk = 48_000

        func samples(_ frames: Range<Int>) throws -> [Float] {
            var out = [Float](repeating: 0, count: frames.count)
            let available = frames.clamped(to: 0..<sourceFrames)
            guard !available.isEmpty else { return out }
            try reader.seek(toOffset: UInt64(StemWriter.dataStart + available.lowerBound * StemWriter.bytesPerSample))
            let data = [UInt8](try reader.read(upToCount: available.count * StemWriter.bytesPerSample) ?? Data())
            for index in 0..<min(available.count, data.count / StemWriter.bytesPerSample) {
                let raw = Int32(data[index * StemWriter.bytesPerSample]) | Int32(data[index * StemWriter.bytesPerSample + 1]) << 8 | Int32(data[index * StemWriter.bytesPerSample + 2]) << 16
                let value = (raw << 8) >> 8  // sign-extend 24 bits
                out[available.lowerBound - frames.lowerBound + index] = Float(value) / 8_388_608
            }
            return out
        }

        for range in ranges {
            var start = range.lowerBound
            let end = min(range.upperBound, Int(targetFrames))
            while start < end {
                let part = start..<min(start + chunk, end)
                try samples(part).withUnsafeBufferPointer { try writer.overwrite($0, atFrame: UInt64(part.lowerBound)) }
                start = part.upperBound
            }
        }
        var next = Int(targetFrames)
        while next < length {
            let part = next..<min(next + chunk, length)
            try samples(part).withUnsafeBufferPointer { try writer.append($0) }
            next = part.upperBound
        }
        try writer.setMarkers(markers)
        try writer.finalize()
    }
}

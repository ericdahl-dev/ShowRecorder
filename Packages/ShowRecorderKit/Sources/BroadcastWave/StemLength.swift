import Foundation

/// Reads a Stem's length from its header without loading the samples.
public enum StemLength {
    /// The number of frames in the mono 24-bit Stem at `url`: its data size ÷ 3. For an RF64 Stem
    /// the data size comes from `ds64`. The size is capped at the bytes actually in the file, so a
    /// Stem cut short by a crash reports what it holds.
    public static func frameCount(at url: URL) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        guard let header = try handle.read(upToCount: 12), header.count == 12,
              header.prefix(4).elementsEqual("RIFF".utf8) || header.prefix(4).elementsEqual("RF64".utf8),
              header.suffix(4).elementsEqual("WAVE".utf8)
        else { throw notAStem(url) }

        var ds64DataSize: UInt64?
        var offset: UInt64 = 12
        while offset + 8 <= fileSize {
            try handle.seek(toOffset: offset)
            guard let chunk = try handle.read(upToCount: 8), chunk.count == 8 else { break }
            let id = chunk.prefix(4)
            var size = littleEndian(chunk.suffix(4))
            let body = offset + 8
            if id.elementsEqual("ds64".utf8), let sizes = try handle.read(upToCount: 16), sizes.count == 16 {
                ds64DataSize = littleEndian(sizes.suffix(8))
            } else if id.elementsEqual("data".utf8) {
                if size == 0xFFFF_FFFF, let ds64DataSize { size = ds64DataSize }
                return min(size, fileSize - body) / UInt64(StemWriter.bytesPerSample)
            }
            offset = body + size + size % 2
        }
        throw notAStem(url)
    }

    private static func littleEndian(_ bytes: Data) -> UInt64 {
        bytes.reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }

    private static func notAStem(_ url: URL) -> CocoaError {
        CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
    }
}

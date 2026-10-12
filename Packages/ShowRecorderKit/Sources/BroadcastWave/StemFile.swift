import Foundation

/// What a Stem file holds, read from its header and size without loading the samples (#440). One walk over the
/// RIFF or RF64 chunks gives both lengths a Stem can have, so each caller says which one it means:
/// - `frameCount`, the length the header declares (capped at the file): what a finished Stem is.
/// - `framesOnDisk`, every whole sample in the file: where writing or Repair resumes in a Stem whose header lags,
///   such as one cut off by a crash before its header was rewritten.
public struct StemFile: Equatable, Sendable {
    /// Where the samples start.
    public let dataStart: UInt64
    /// The data size the header declares (from `ds64` for RF64). Behind the samples in a Stem cut off by a crash.
    public let declaredBytes: UInt64
    /// The bytes from `dataStart` to the end of the file. The data chunk is a Stem's last, so these are its samples
    /// plus at most a pad byte.
    public let bytesOnDisk: UInt64

    /// Reads the Stem at `url`. Throws when the file can't be read or isn't a WAV with a data chunk.
    public static func inspect(_ url: URL) throws -> StemFile {
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
                return StemFile(dataStart: body, declaredBytes: size, bytesOnDisk: fileSize - body)
            }
            offset = body + size + size % 2
        }
        throw notAStem(url)
    }

    /// The frames the header declares, capped at the bytes really in the file: a finished Stem's length.
    public var frameCount: UInt64 { audioRegion.length / UInt64(StemWriter.bytesPerSample) }

    /// Every whole sample in the file, whatever the header says. A half-written sample or the pad byte is ignored.
    public var framesOnDisk: UInt64 { bytesOnDisk / UInt64(StemWriter.bytesPerSample) }

    /// Where the samples are: the start of the data chunk and the bytes the header declares, capped at the file.
    public var audioRegion: (offset: UInt64, length: UInt64) { (dataStart, min(declaredBytes, bytesOnDisk)) }

    private static func littleEndian(_ bytes: Data) -> UInt64 {
        bytes.reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }

    private static func notAStem(_ url: URL) -> CocoaError {
        CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
    }
}

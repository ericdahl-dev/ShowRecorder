import Foundation

/// Writes one mono 24-bit Broadcast WAV file: a Stem (ADR 0001).
///
/// Not real-time safe; used on the writer thread. Samples arrive as 32-bit float and are
/// converted as `x × 2²³`, rounded and clamped to the 24-bit range.
///
/// A Stem starts as plain RIFF/WAVE with a 28-byte `JUNK` chunk reserved right after `WAVE`.
/// Just before the RIFF size would pass the 32-bit limit (about 8 hours at 48 kHz), the Stem is
/// promoted to RF64 (EBU Tech 3306): `RIFF` becomes `RF64`, `JUNK` becomes `ds64` holding the
/// 64-bit sizes, and the 32-bit RIFF and data sizes are set to 0xFFFFFFFF. The Take keeps
/// recording into the same file with no gap.
public final class StemWriter: StemSink {
    public struct Info: Sendable {
        public var sampleRate: Int
        /// The Source name, stored as the bext description.
        public var description: String
        public var originator: String
        /// Samples since local midnight at the start of the Take. Identical across a Take's Stems.
        public var timeReference: UInt64
        public var originationDate: Date

        public init(sampleRate: Int, description: String, originator: String, timeReference: UInt64, originationDate: Date) {
            self.sampleRate = sampleRate
            self.description = description
            self.originator = originator
            self.timeReference = timeReference
            self.originationDate = originationDate
        }

        /// This info with another Source name as the description.
        public func described(_ description: String) -> Info {
            var copy = self
            copy.description = description
            return copy
        }
    }

    public let url: URL
    public private(set) var frameCount: UInt64 = 0

    /// Whether the Stem has been promoted to RF64.
    private(set) var isRF64 = false

    private let handle: FileHandle
    private var bytes: [UInt8] = []
    private let dataSizeOffset: UInt64
    private let markerRegionOffset: UInt64
    /// The RIFF size (bytes after the size field) a plain RIFF Stem must stay below.
    /// 0xFFFFFFFF itself is RF64's "see ds64" value, so it is never written as a real size.
    private let rf64Threshold: UInt64

    public convenience init(url: URL, info: Info) throws {
        try self.init(url: url, info: info, rf64Threshold: Self.maxRIFFSize)
    }

    /// `rf64Threshold` is the RIFF size at which the Stem is promoted to RF64. Tests lower it
    /// so promotion can be checked without writing 4 GB.
    init(url: URL, info: Info, rf64Threshold: UInt64) throws {
        precondition(rf64Threshold <= Self.maxRIFFSize)
        self.url = url
        self.rf64Threshold = rf64Threshold
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        handle = try FileHandle(forWritingTo: url)
        let header = Self.header(info: info)
        try handle.write(contentsOf: header.bytes)
        dataSizeOffset = UInt64(header.dataSizeOffset)
        markerRegionOffset = UInt64(header.markerRegionOffset)
    }

    /// A new Stem, or, when `frames` is given, the Stem at `url` reopened to carry on after its first
    /// `frames` samples (for a Destination that failed and came back). Anything past those samples
    /// (a half-written sample, a padding byte) is cut off.
    public static func open(url: URL, info: Info, resumingAt frames: UInt64?) throws -> StemWriter {
        guard let frames else { return try StemWriter(url: url, info: info) }
        return try StemWriter(resuming: url, info: info, frameCount: frames, rf64Threshold: maxRIFFSize)
    }

    private init(resuming url: URL, info: Info, frameCount: UInt64, rf64Threshold: UInt64) throws {
        self.url = url
        self.rf64Threshold = rf64Threshold
        handle = try FileHandle(forUpdating: url)
        let header = Self.header(info: info)
        dataSizeOffset = UInt64(header.dataSizeOffset)
        markerRegionOffset = UInt64(header.markerRegionOffset)
        let end = UInt64(header.bytes.count) + frameCount * UInt64(Self.bytesPerSample)
        try handle.truncate(atOffset: end)
        try handle.seek(toOffset: 0)
        isRF64 = try handle.read(upToCount: 4) == Data("RF64".utf8)
        try handle.seek(toOffset: end)
        self.frameCount = frameCount
    }

    /// Writes `markers` as `cue ` points with `LIST/adtl` labels into the region reserved before the
    /// audio, replacing any written before. The region is rewritten in place, so Markers are as
    /// crash-safe as the chunk sizes: they're on disk from the next header commit.
    ///
    /// Returns how many Markers fit. The region holds a few hundred; any that don't fit are left out
    /// of the Stem (newest first) and stay in the Take's metadata.
    @discardableResult
    public func setMarkers(_ markers: [StemMarker]) throws -> Int {
        // The largest prefix of `markers` that fits (binary search; the region size grows with count).
        var low = 0, high = markers.count
        while low < high {
            let mid = (low + high + 1) / 2
            if Self.markerRegion(Array(markers.prefix(mid))) != nil { low = mid } else { high = mid - 1 }
        }
        let region = Self.markerRegion(Array(markers.prefix(low))) ?? Self.markerRegion([])!
        let end = try handle.offset()
        try handle.seek(toOffset: markerRegionOffset)
        try handle.write(contentsOf: region)
        try handle.seek(toOffset: end)
        return low
    }

    private func encode(_ samples: UnsafeBufferPointer<Float>) {
        bytes.removeAll(keepingCapacity: true)
        bytes.reserveCapacity(samples.count * Self.bytesPerSample)
        for sample in samples {
            let value = Int32(max(-8_388_608, min(8_388_607, (Double(sample) * 8_388_608).rounded())))
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
            bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        }
    }

    /// Replaces samples already written, starting at `frame`, without moving the write position.
    /// Used by Repair to fill a Gap in place.
    public func overwrite(_ samples: UnsafeBufferPointer<Float>, atFrame frame: UInt64) throws {
        precondition(frame + UInt64(samples.count) <= frameCount, "overwrite past the end of the Stem")
        encode(samples)
        let end = try handle.offset()
        try handle.seek(toOffset: UInt64(Self.dataStart) + frame * UInt64(Self.bytesPerSample))
        try handle.write(contentsOf: bytes)
        try handle.seek(toOffset: end)
    }

    /// Reopens the Stem at `url` to write into it again: `overwrite` over its Gaps, `append` after its
    /// last whole sample. The header is kept as it is; only the sizes are rewritten at `finalize`.
    public static func reopen(url: URL) throws -> StemWriter {
        guard let frames = frameCount(of: url) else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path]) }
        // A resumed Stem keeps its own header, so this Info is only used to find where the sizes and
        // Marker region are, and is the same for every Stem.
        let info = Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: Date(timeIntervalSince1970: 0))
        return try open(url: url, info: info, resumingAt: frames)
    }

    /// The samples of `frames` (counted from the start of the Stem) in the Stem at `url`, as Floats in
    /// -1...1. Frames past the end of the Stem read as silence. Works on plain RIFF and RF64 Stems alike.
    public static func readSamples(url: URL, frames: Range<Int>) throws -> [Float] {
        var out = [Float](repeating: 0, count: frames.count)
        let available = frames.clamped(to: 0..<Int(frameCount(of: url) ?? 0))
        guard !available.isEmpty else {
            if frameCount(of: url) == nil { throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path]) }
            return out
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(dataStart + available.lowerBound * bytesPerSample))
        let data = [UInt8](try handle.read(upToCount: available.count * bytesPerSample) ?? Data())
        for index in 0..<min(available.count, data.count / bytesPerSample) {
            let base = index * bytesPerSample
            let raw = Int32(data[base]) | Int32(data[base + 1]) << 8 | Int32(data[base + 2]) << 16
            out[available.lowerBound - frames.lowerBound + index] = Float((raw << 8) >> 8) / 8_388_608  // sign-extend 24 bits
        }
        return out
    }

    /// Samples in the Stem file at `url`, from its size, or nil if it can't be read. Counts only whole
    /// samples, so a half-written one or the padding byte after an odd count is ignored.
    public static func frameCount(of url: URL) -> UInt64? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size >= UInt64(dataStart) else { return nil }
        return (size - UInt64(dataStart)) / UInt64(bytesPerSample)
    }

    /// Bytes in one 24-bit sample: the one place that figure lives.
    public static let bytesPerSample = 3

    /// Where the audio starts in every Stem, plain RIFF or RF64: the header is the same length for all of them.
    static let dataStart = header(info: Info(sampleRate: 48_000, description: "", originator: "", timeReference: 0, originationDate: Date(timeIntervalSince1970: 0))).bytes.count

    /// Appends samples. Values outside -1...1 are clamped.
    public func append(_ samples: UnsafeBufferPointer<Float>) throws {
        encode(samples)
        try promoteIfNeeded(riffEnd: try handle.offset() + UInt64(bytes.count))
        try handle.write(contentsOf: bytes)
        frameCount += UInt64(samples.count)
    }

    /// Rewrites the chunk sizes to cover every sample appended so far and flushes to disk.
    /// If the app dies later, the file still plays up to this point.
    public func commitHeader() throws {
        let end = try handle.offset()
        try writeSizes(dataBytes: frameCount * UInt64(Self.bytesPerSample), riffEnd: end)
        try handle.synchronize()
        try handle.seek(toOffset: end)
    }

    /// Writes the final chunk sizes and closes the file.
    public func finalize() throws {
        let dataBytes = frameCount * UInt64(Self.bytesPerSample)
        if dataBytes % 2 == 1 {
            try promoteIfNeeded(riffEnd: try handle.offset() + 1)
            try handle.write(contentsOf: [0])
        }
        try writeSizes(dataBytes: dataBytes, riffEnd: try handle.offset())
        try handle.close()
    }

    /// RIFF size counts everything after its own field up to `riffEnd`; data size is the sample bytes.
    private func writeSizes(dataBytes: UInt64, riffEnd: UInt64) throws {
        if isRF64 {
            // One write: the ds64 RIFF size, data size and sample count change together.
            try handle.seek(toOffset: Self.ds64BodyOffset)
            try handle.write(contentsOf: ds64Sizes(dataBytes: dataBytes, riffEnd: riffEnd))
        } else {
            try handle.seek(toOffset: 4)
            try handle.write(contentsOf: UInt32(riffEnd - 8).littleEndianBytes)
            try handle.seek(toOffset: dataSizeOffset)
            try handle.write(contentsOf: UInt32(dataBytes).littleEndianBytes)
        }
    }

    /// Promotes the Stem to RF64 if a RIFF ending at `riffEnd` would reach the threshold.
    ///
    /// Promotion is also a header commit covering everything appended so far. It is ordered so
    /// that a crash between steps leaves a readable file:
    /// 1. One write of the first 48 bytes: `RF64`, 0xFFFFFFFF, `WAVE`, then `ds64` with the
    ///    current sizes over the reserved `JUNK`. The 32-bit data size is still correct here.
    /// 2. The 32-bit data size becomes 0xFFFFFFFF, deferring to ds64.
    /// Each step is one write within the first filesystem block, flushed before the next.
    private func promoteIfNeeded(riffEnd: UInt64) throws {
        guard !isRF64, riffEnd - 8 >= rf64Threshold else { return }
        let end = try handle.offset()
        var head: [UInt8] = Array("RF64".utf8) + UInt32.max.littleEndianBytes + Array("WAVE".utf8)
        head += Array("ds64".utf8) + UInt32(Self.ds64BodySize).littleEndianBytes
        head += ds64Sizes(dataBytes: frameCount * UInt64(Self.bytesPerSample), riffEnd: end)
        head += UInt32(0).littleEndianBytes  // table length
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: head)
        try handle.synchronize()
        try handle.seek(toOffset: dataSizeOffset)
        try handle.write(contentsOf: UInt32.max.littleEndianBytes)
        try handle.synchronize()
        try handle.seek(toOffset: end)
        isRF64 = true
    }

    /// The ds64 RIFF size, data size and sample count (one sample per frame in a mono Stem).
    private func ds64Sizes(dataBytes: UInt64, riffEnd: UInt64) -> [UInt8] {
        (riffEnd - 8).littleEndianBytes + dataBytes.littleEndianBytes + frameCount.littleEndianBytes
    }

    // MARK: - Header

    static let maxRIFFSize = UInt64(UInt32.max)
    /// RIFF size, data size, sample count (8 bytes each) and table length (4 bytes).
    private static let ds64BodySize = 28
    private static let ds64BodyOffset: UInt64 = 20

    /// Bytes reserved before `data` for Markers (`cue ` and `LIST/adtl` chunks, padded with `JUNK`).
    static let markerRegionSize = 16_384

    /// The marker region for `markers`, exactly `markerRegionSize` bytes, or nil if they don't fit.
    static func markerRegion(_ markers: [StemMarker]) -> [UInt8]? {
        var out: [UInt8] = []
        if !markers.isEmpty {
            out += Array("cue ".utf8) + UInt32(4 + 24 * markers.count).littleEndianBytes
            out += UInt32(markers.count).littleEndianBytes
            for (index, marker) in markers.enumerated() {
                out += UInt32(index + 1).littleEndianBytes        // cue point id
                out += marker.position.littleEndianBytes          // play-order position
                out += Array("data".utf8)
                out += UInt32(0).littleEndianBytes + UInt32(0).littleEndianBytes  // chunk start, block start
                out += marker.position.littleEndianBytes          // sample offset
            }
            var labels: [UInt8] = Array("adtl".utf8)
            for (index, marker) in markers.enumerated() {
                let text = Array(marker.label.utf8) + [0]
                labels += Array("labl".utf8) + UInt32(4 + text.count).littleEndianBytes
                labels += UInt32(index + 1).littleEndianBytes + text
                if text.count % 2 == 1 { labels.append(0) }
            }
            out += Array("LIST".utf8) + UInt32(labels.count).littleEndianBytes + labels
        }
        let padding = markerRegionSize - out.count
        guard padding == 0 || padding >= 8 else { return nil }
        if padding > 0 {
            out += Array("JUNK".utf8) + UInt32(padding - 8).littleEndianBytes + [UInt8](repeating: 0, count: padding - 8)
        }
        return out
    }

    private static func header(info: Info) -> (bytes: [UInt8], dataSizeOffset: Int, markerRegionOffset: Int) {
        var out: [UInt8] = []
        out += Array("RIFF".utf8) + UInt32(0).littleEndianBytes + Array("WAVE".utf8)

        // Reserved for ds64, which must be the first chunk after WAVE (EBU Tech 3306).
        out += Array("JUNK".utf8) + UInt32(ds64BodySize).littleEndianBytes
        out += [UInt8](repeating: 0, count: ds64BodySize)

        // fmt: PCM, mono, 24-bit
        out += Array("fmt ".utf8) + UInt32(16).littleEndianBytes
        out += UInt16(1).littleEndianBytes + UInt16(1).littleEndianBytes
        out += UInt32(info.sampleRate).littleEndianBytes
        out += UInt32(info.sampleRate * Self.bytesPerSample).littleEndianBytes
        out += UInt16(3).littleEndianBytes + UInt16(24).littleEndianBytes

        // bext (EBU Tech 3285 v2), 602 bytes with no coding history
        var bext: [UInt8] = []
        bext += fixed(info.description, 256)
        bext += fixed(info.originator, 32)
        bext += fixed("", 32)  // originator reference
        let (date, time) = originationStamp(info.originationDate)
        bext += fixed(date, 10) + fixed(time, 8)
        bext += UInt32(truncatingIfNeeded: info.timeReference).littleEndianBytes
        bext += UInt32(truncatingIfNeeded: info.timeReference >> 32).littleEndianBytes
        bext += UInt16(2).littleEndianBytes  // version
        bext += [UInt8](repeating: 0, count: 64 + 10 + 180)  // UMID, loudness, reserved
        out += Array("bext".utf8) + UInt32(bext.count).littleEndianBytes + bext

        let markerRegionOffset = out.count
        out += markerRegion([])!

        out += Array("data".utf8)
        let dataSizeOffset = out.count
        out += UInt32(0).littleEndianBytes
        return (out, dataSizeOffset, markerRegionOffset)
    }

    private static func fixed(_ string: String, _ length: Int) -> [UInt8] {
        var bytes = Array(string.utf8.prefix(length))
        bytes += [UInt8](repeating: 0, count: length - bytes.count)
        return bytes
    }

    private static func originationStamp(_ date: Date) -> (String, String) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let time = String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return (day, time)
    }
}

extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }
}

/// What a Take writer needs from a Stem file. `StemWriter` is the real one; tests substitute Stems
/// that fail, to stand in for a Destination that goes away.
public protocol StemSink: AnyObject {
    /// Samples written so far.
    var frameCount: UInt64 { get }
    func append(_ samples: UnsafeBufferPointer<Float>) throws
    func commitHeader() throws
    func finalize() throws
    @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int
}

/// A named point in a Stem, in samples from the start of the Take.
public struct StemMarker: Equatable, Sendable {
    public var position: UInt32
    public var label: String

    public init(position: UInt32, label: String) {
        self.position = position
        self.label = label
    }
}

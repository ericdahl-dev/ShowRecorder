import Foundation

/// Writes one mono 24-bit Broadcast WAV file: a Stem (ADR 0001).
///
/// Not real-time safe; used on the writer thread. Samples arrive as 32-bit float and are
/// converted as `x × 2²³`, rounded and clamped to the 24-bit range.
public final class StemWriter {
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
    }

    public let url: URL
    public private(set) var frameCount: UInt64 = 0

    private let handle: FileHandle
    private var bytes: [UInt8] = []
    private let dataSizeOffset: UInt64

    public init(url: URL, info: Info) throws {
        self.url = url
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        handle = try FileHandle(forWritingTo: url)
        let header = Self.header(info: info)
        try handle.write(contentsOf: header.bytes)
        dataSizeOffset = UInt64(header.dataSizeOffset)
    }

    /// Appends samples. Values outside -1...1 are clamped.
    public func append(_ samples: UnsafeBufferPointer<Float>) throws {
        bytes.removeAll(keepingCapacity: true)
        bytes.reserveCapacity(samples.count * 3)
        for sample in samples {
            let value = Int32(max(-8_388_608, min(8_388_607, (Double(sample) * 8_388_608).rounded())))
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
            bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        }
        try handle.write(contentsOf: bytes)
        frameCount += UInt64(samples.count)
    }

    /// Rewrites the chunk sizes to cover every sample appended so far and flushes to disk.
    /// If the app dies later, the file still plays up to this point.
    public func commitHeader() throws {
        let end = try handle.offset()
        try writeSizes(dataBytes: frameCount * 3, riffEnd: end)
        try handle.synchronize()
        try handle.seek(toOffset: end)
    }

    /// Writes the final chunk sizes and closes the file.
    public func finalize() throws {
        let dataBytes = frameCount * 3
        if dataBytes % 2 == 1 { try handle.write(contentsOf: [0]) }
        try writeSizes(dataBytes: dataBytes, riffEnd: try handle.offset())
        try handle.close()
    }

    /// RIFF size counts everything after its own field up to `riffEnd`; data size is the sample bytes.
    private func writeSizes(dataBytes: UInt64, riffEnd: UInt64) throws {
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: UInt32(truncatingIfNeeded: riffEnd - 8).littleEndianBytes)
        try handle.seek(toOffset: dataSizeOffset)
        try handle.write(contentsOf: UInt32(truncatingIfNeeded: dataBytes).littleEndianBytes)
    }

    // MARK: - Header

    private static func header(info: Info) -> (bytes: [UInt8], dataSizeOffset: Int) {
        var out: [UInt8] = []
        out += Array("RIFF".utf8) + UInt32(0).littleEndianBytes + Array("WAVE".utf8)

        // fmt: PCM, mono, 24-bit
        out += Array("fmt ".utf8) + UInt32(16).littleEndianBytes
        out += UInt16(1).littleEndianBytes + UInt16(1).littleEndianBytes
        out += UInt32(info.sampleRate).littleEndianBytes
        out += UInt32(info.sampleRate * 3).littleEndianBytes
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

        out += Array("data".utf8)
        let dataSizeOffset = out.count
        out += UInt32(0).littleEndianBytes
        return (out, dataSizeOffset)
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

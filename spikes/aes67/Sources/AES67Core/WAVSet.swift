import Foundation

/// One mono 24-bit WAV per channel. Takes interleaved big-endian L24 (or L16) payloads and writes
/// little-endian samples, buffered, patching the RIFF sizes on `close()`.
public final class WAVSet: FrameSink {
    public let channels: Int
    public let sampleRate: Int
    public let inBytes: Int
    private var handles: [FileHandle] = []
    private var buffers: [[UInt8]]
    private var frames: Int64 = 0
    private let flushBytes = 1 << 16

    public init(directory: URL, prefix: String, channels: Int, sampleRate: Int, inBytesPerSample: Int) throws {
        self.channels = channels
        self.sampleRate = sampleRate
        self.inBytes = inBytesPerSample
        buffers = Array(repeating: [], count: channels)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for c in 0..<channels {
            let url = directory.appendingPathComponent(String(format: "%@-ch%02d.wav", prefix, c + 1))
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let h = try FileHandle(forWritingTo: url)
            h.write(Data(Self.header(dataBytes: 0, sampleRate: sampleRate)))
            handles.append(h)
            buffers[c].reserveCapacity(flushBytes + 4096)
        }
    }

    static func header(dataBytes: UInt32, sampleRate: Int) -> [UInt8] {
        var h = [UInt8]()
        func u32(_ v: UInt32) { h += [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)] }
        func u16(_ v: UInt16) { h += [UInt8(v & 0xFF), UInt8(v >> 8)] }
        h += Array("RIFF".utf8); u32(36 + dataBytes); h += Array("WAVE".utf8)
        h += Array("fmt ".utf8); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 3)); u16(3); u16(24)
        h += Array("data".utf8); u32(dataBytes)
        return h
    }

    public func write(payload: ArraySlice<UInt8>, frames n: Int) {
        payload.withUnsafeBufferPointer { p in
            let stride = channels * inBytes
            for c in 0..<channels {
                var i = c * inBytes
                for _ in 0..<n {
                    if inBytes == 3 {
                        buffers[c].append(p[i + 2]); buffers[c].append(p[i + 1]); buffers[c].append(p[i])
                    } else {
                        buffers[c].append(0); buffers[c].append(p[i + 1]); buffers[c].append(p[i])
                    }
                    i += stride
                }
            }
        }
        frames += Int64(n)
        if buffers[0].count >= flushBytes { flush() }
    }

    public func writeSilence(frames n: Int) {
        for c in 0..<channels { buffers[c].append(contentsOf: repeatElement(0, count: n * 3)) }
        frames += Int64(n)
        if buffers[0].count >= flushBytes { flush() }
    }

    private func flush() {
        for c in 0..<channels where !buffers[c].isEmpty {
            handles[c].write(Data(buffers[c]))
            buffers[c].removeAll(keepingCapacity: true)
        }
    }

    public var framesWritten: Int64 { frames }

    public func close() throws {
        flush()
        let dataBytes = UInt32(clamping: frames * 3)
        for h in handles {
            try h.seek(toOffset: 0)
            h.write(Data(Self.header(dataBytes: dataBytes, sampleRate: sampleRate)))
            try h.close()
        }
    }
}

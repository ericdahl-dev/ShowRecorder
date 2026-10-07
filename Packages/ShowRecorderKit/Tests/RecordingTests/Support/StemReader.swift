import Foundation

/// A minimal Broadcast WAV reader for tests: format, bext fields and 24-bit samples.
struct StemFile {
    var channelCount: Int
    var sampleRate: Int
    var bitsPerSample: Int
    var description: String
    var originator: String
    var timeReference: UInt64
    /// Samples as signed 24-bit integers.
    var samples: [Int32]

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count >= 12, data.string(at: 0, length: 4) == "RIFF", data.string(at: 8, length: 4) == "WAVE" else {
            throw StemReadError.notWave
        }
        var channelCount = 0, sampleRate = 0, bitsPerSample = 0
        var description = "", originator = "", timeReference: UInt64 = 0
        var samples: [Int32] = []
        var offset = 12
        while offset + 8 <= data.count {
            let id = data.string(at: offset, length: 4)
            let size = Int(data.uint32(at: offset + 4))
            let body = offset + 8
            switch id {
            case "fmt ":
                channelCount = Int(data.uint16(at: body + 2))
                sampleRate = Int(data.uint32(at: body + 4))
                bitsPerSample = Int(data.uint16(at: body + 14))
            case "bext":
                description = data.string(at: body, length: 256)
                originator = data.string(at: body + 256, length: 32)
                timeReference = UInt64(data.uint32(at: body + 338)) | (UInt64(data.uint32(at: body + 342)) << 32)
            case "data":
                let end = min(body + size, data.count)
                var i = body
                while i + 3 <= end {
                    let raw = Int32(data[i]) | (Int32(data[i + 1]) << 8) | (Int32(data[i + 2]) << 16)
                    samples.append((raw << 8) >> 8)  // sign-extend 24 bits
                    i += 3
                }
            default:
                break
            }
            offset = body + size + (size % 2)
        }
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.bitsPerSample = bitsPerSample
        self.description = description
        self.originator = originator
        self.timeReference = timeReference
        self.samples = samples
    }
}

enum StemReadError: Error { case notWave }

private extension Data {
    func string(at offset: Int, length: Int) -> String {
        let bytes = self[(startIndex + offset)..<(startIndex + offset + length)].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }
    func uint32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) }
    }
}

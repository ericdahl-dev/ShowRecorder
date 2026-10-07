import Foundation

/// Reads the cue points and their labels from a WAV/RF64 file's chunks before the audio.
struct CuePoints: Equatable {
    struct Point: Equatable {
        var position: UInt32
        var label: String
    }

    var points: [Point]

    init(contentsOf url: URL) throws {
        let data = [UInt8](try Data(contentsOf: url))
        func u32(_ i: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(data[i + $1]) << (8 * $1) } }
        func id(_ i: Int) -> String { String(decoding: data[i..<i + 4], as: UTF8.self) }
        var positions: [UInt32: UInt32] = [:]   // cue id → position
        var labels: [UInt32: String] = [:]
        var offset = 12
        while offset + 8 <= data.count {
            let chunk = id(offset)
            let size = Int(u32(offset + 4))
            let body = offset + 8
            if chunk == "data" { break }
            if chunk == "cue " {
                let count = Int(u32(body))
                for n in 0..<count {
                    let p = body + 4 + n * 24
                    positions[u32(p)] = u32(p + 20)
                }
            } else if chunk == "LIST", id(body) == "adtl" {
                var sub = body + 4
                while sub + 8 <= body + size {
                    let subSize = Int(u32(sub + 4))
                    if id(sub) == "labl" {
                        let text = data[(sub + 12)..<(sub + 8 + subSize)].prefix { $0 != 0 }
                        labels[u32(sub + 8)] = String(decoding: text, as: UTF8.self)
                    }
                    sub += 8 + subSize + (subSize % 2)
                }
            }
            offset = body + size + (size % 2)
        }
        points = positions.keys.sorted().map { Point(position: positions[$0]!, label: labels[$0] ?? "") }
    }
}

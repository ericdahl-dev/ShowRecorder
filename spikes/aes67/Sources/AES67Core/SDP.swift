import Foundation

/// The parts of an AES67 SDP the receiver needs.
public struct StreamDescription: Equatable {
    public var group: String
    public var port: UInt16
    public var payloadType: UInt8
    public var encoding: String
    public var sampleRate: Int
    public var channels: Int
    public var ptimeMs: Double?
    public var sourceFilter: String?
    /// `a=ts-refclk`, e.g. `ptp=IEEE1588-2008:39-A7-94-FF-FE-07-CB-D0:0`.
    public var refClock: String?
    /// `a=mediaclk`, e.g. `direct=0` (RTP timestamp = PTP time in samples + offset).
    public var mediaClock: String?

    public var bytesPerSample: Int { encoding == "L16" ? 2 : 3 }
}

public enum SDPError: Error, Equatable {
    case missing(String)
    case unsupported(String)
}

public func parseSDP(_ text: String) throws -> StreamDescription {
    var group: String?
    var port: UInt16?
    var pt: UInt8?
    var encoding: String?
    var rate: Int?
    var channels = 1
    var ptime: Double?
    var filter: String?
    var refclk: String?
    var mediaclk: String?

    for raw in text.split(whereSeparator: \.isNewline) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("c=") {
            // c=IN IP4 239.69.83.67/32
            let parts = line.dropFirst(2).split(separator: " ")
            if parts.count >= 3 { group = String(parts[2].split(separator: "/")[0]) }
        } else if line.hasPrefix("m=audio ") {
            // m=audio 5004 RTP/AVP 98
            let parts = line.dropFirst(2).split(separator: " ")
            if parts.count >= 4 {
                port = UInt16(parts[1])
                pt = UInt8(parts[3])
            }
        } else if line.hasPrefix("a=rtpmap:") {
            // a=rtpmap:98 L24/48000/8
            let body = line.dropFirst("a=rtpmap:".count)
            let parts = body.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if let pt, UInt8(parts[0]) != pt { continue }
            let fmt = parts[1].split(separator: "/")
            encoding = String(fmt[0])
            if fmt.count > 1 { rate = Int(fmt[1]) }
            if fmt.count > 2 { channels = Int(fmt[2]) ?? 1 }
        } else if line.hasPrefix("a=ptime:") {
            ptime = Double(line.dropFirst("a=ptime:".count))
        } else if line.hasPrefix("a=source-filter:") {
            filter = String(line.dropFirst("a=source-filter:".count)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("a=ts-refclk:") {
            refclk = String(line.dropFirst("a=ts-refclk:".count))
        } else if line.hasPrefix("a=mediaclk:") {
            mediaclk = String(line.dropFirst("a=mediaclk:".count))
        }
    }
    guard let group else { throw SDPError.missing("c=") }
    guard let port, let pt else { throw SDPError.missing("m=audio") }
    guard let encoding, let rate else { throw SDPError.missing("a=rtpmap") }
    guard encoding == "L24" || encoding == "L16" else { throw SDPError.unsupported(encoding) }
    return StreamDescription(group: group, port: port, payloadType: pt, encoding: encoding, sampleRate: rate,
                             channels: channels, ptimeMs: ptime, sourceFilter: filter, refClock: refclk,
                             mediaClock: mediaclk)
}

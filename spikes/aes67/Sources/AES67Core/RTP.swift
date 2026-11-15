/// One RTP header (RFC 3550). `payload` is the byte range of the audio in the datagram.
public struct RTPHeader: Equatable {
    public var payloadType: UInt8
    public var marker: Bool
    public var sequence: UInt16
    public var timestamp: UInt32
    public var ssrc: UInt32
    public var payload: Range<Int>
}

public func parseRTP(_ b: UnsafeRawBufferPointer) -> RTPHeader? {
    guard b.count >= 12, b[0] >> 6 == 2 else { return nil }
    let padding = b[0] & 0x20 != 0
    let ext = b[0] & 0x10 != 0
    let csrc = Int(b[0] & 0x0F)
    var start = 12 + csrc * 4
    guard b.count >= start else { return nil }
    if ext {
        guard b.count >= start + 4 else { return nil }
        let words = Int(b[start + 2]) << 8 | Int(b[start + 3])
        start += 4 + words * 4
    }
    var end = b.count
    if padding, end > start { end -= Int(b[end - 1]) }
    guard end >= start else { return nil }
    func u16(_ i: Int) -> UInt16 { UInt16(b[i]) << 8 | UInt16(b[i + 1]) }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) << 16 | UInt32(u16(i + 2)) }
    return RTPHeader(payloadType: b[1] & 0x7F, marker: b[1] & 0x80 != 0, sequence: u16(2), timestamp: u32(4),
                     ssrc: u32(8), payload: start..<end)
}

/// Turns a wrapping 16-bit sequence number or 32-bit timestamp into a 64-bit count, relative to the
/// highest value seen so far (so an old, reordered value maps below it rather than a whole wrap above).
public struct Unwrapper {
    public let bits: Int
    private var highest: Int64?
    public init(bits: Int) { self.bits = bits }

    public mutating func extend(_ value: UInt64) -> Int64 {
        let modulus = Int64(1) << bits
        let v = Int64(value) & (modulus - 1)
        guard let h = highest else {
            highest = v
            return v
        }
        var delta = (v - h) & (modulus - 1)
        if delta >= modulus / 2 { delta -= modulus }
        let e = h + delta
        if e > h { highest = e }
        return e
    }
}

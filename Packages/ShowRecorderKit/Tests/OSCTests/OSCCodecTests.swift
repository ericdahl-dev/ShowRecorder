import Foundation
import OSC
import Testing

@Suite("OSC codec")
struct OSCCodecTests {
    static func bytes(_ hex: String) -> [UInt8] {
        let digits = hex.filter { !$0.isWhitespace }
        return stride(from: 0, to: digits.count, by: 2).map {
            let start = digits.index(digits.startIndex, offsetBy: $0)
            return UInt8(digits[start...digits.index(after: start)], radix: 16)!
        }
    }

    @Test("A query with no arguments: address padded to 4 bytes, empty type tag")
    func queryWithNoArguments() throws {
        let message = OSCMessage("/xinfo")
        // "/xinfo" + 2 NULs, then "," + 3 NULs.
        let expected = Self.bytes("2f78696e 666f0000 2c000000")

        #expect(message.encoded() == expected)
        #expect(try OSCMessage(decoding: expected) == message)
    }

    @Test("String, int and float arguments round-trip")
    func stringIntFloatRoundTrip() throws {
        let message = OSCMessage("/ch/07/config/name", ["Vox", .int(3), .float(0.75)])
        let expected = Self.bytes("""
            2f63682f 30372f63 6f6e6669 672f6e61 6d650000
            2c736966 00000000
            566f7800
            00000003
            3f400000
            """)

        #expect(message.encoded() == expected)
        #expect(try OSCMessage(decoding: expected) == message)
    }

    @Test("A string that fills four bytes still gets a terminating NUL word")
    func stringOnBoundaryGetsTerminator() throws {
        let message = OSCMessage("/a", ["abcd"])
        let expected = Self.bytes("2f610000 2c730000 61626364 00000000")

        #expect(message.encoded() == expected)
        #expect(try OSCMessage(decoding: expected) == message)
    }

    /// A bundle of `depth` bundles, one inside the next, around one message.
    static func nestedBundle(depth: Int) -> [UInt8] {
        var packet = OSCMessage("/a", [.int(1)]).encoded()
        for _ in 0..<depth {
            packet = bytes("2362756e 646c6500 00000000 00000001") + withUnsafeBytes(of: UInt32(packet.count).bigEndian) { Array($0) } + packet
        }
        return packet
    }

    @Test("Bundles and blobs are refused, not decoded: neither mixer sends them, and nested bundles could crash the app (#886)")
    func bundlesAndBlobsRefused() {
        #expect(throws: OSCError.self) { try OSCPacket(decoding: Self.nestedBundle(depth: 1)) }
        // About as deep as one 64 KB datagram allows: refused at once, with no recursion.
        #expect(throws: OSCError.self) { try OSCPacket(decoding: Self.nestedBundle(depth: 3_000)) }
        #expect(throws: OSCError.self) { try OSCMessage(decoding: Self.bytes("2f620000 2c620000 00000005 01020304 05000000")) }
    }

    @Test("Truncated or malformed data throws instead of crashing", arguments: [
        "2f78",                       // address with no terminator
        "2f610000",                   // no type tag
        "2f610000 2c690000 0000",     // int cut short
        "2f610000 2c780000",          // unknown type tag
    ])
    func malformedDataThrows(hex: String) {
        #expect(throws: OSCError.self) { try OSCMessage(decoding: Self.bytes(hex)) }
    }
}

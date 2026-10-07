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

    @Test("Blobs carry a length and are padded")
    func blobRoundTrip() throws {
        let message = OSCMessage("/b", [.blob([1, 2, 3, 4, 5])])
        let expected = Self.bytes("2f620000 2c620000 00000005 01020304 05000000")

        #expect(message.encoded() == expected)
        #expect(try OSCMessage(decoding: expected) == message)
    }

    @Test("A bundle decodes into its messages")
    func bundleDecodes() throws {
        let first = OSCMessage("/a", [.int(1)])
        let second = OSCMessage("/b", ["x"])
        var packet = Self.bytes("2362756e 646c6500 00000000 00000001")  // "#bundle", timetag "immediately"
        for message in [first, second] {
            let element = message.encoded()
            packet += withUnsafeBytes(of: UInt32(element.count).bigEndian) { Array($0) } + element
        }

        #expect(try OSCPacket(decoding: packet) == .bundle([.message(first), .message(second)]))
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

/// One OSC argument. Strings can be written as literals: `OSCMessage("/a", ["text"])`.
public enum OSCArgument: Equatable, Sendable, ExpressibleByStringLiteral {
    case int(Int32)
    case float(Float)
    case string(String)
    case blob([UInt8])

    public init(stringLiteral value: String) { self = .string(value) }

    var typeTag: UInt8 {
        switch self {
        case .int: UInt8(ascii: "i")
        case .float: UInt8(ascii: "f")
        case .string: UInt8(ascii: "s")
        case .blob: UInt8(ascii: "b")
        }
    }
}

/// An OSC message: an address and arguments.
public struct OSCMessage: Equatable, Sendable {
    public var address: String
    public var arguments: [OSCArgument]

    public init(_ address: String, _ arguments: [OSCArgument] = []) {
        self.address = address
        self.arguments = arguments
    }

    public func encoded() -> [UInt8] {
        var out: [UInt8] = []
        out.appendOSCString(address)
        out.appendOSCString("," + String(decoding: arguments.map(\.typeTag), as: UTF8.self))
        for argument in arguments {
            switch argument {
            case .int(let value): out.appendBigEndian(UInt32(bitPattern: value))
            case .float(let value): out.appendBigEndian(value.bitPattern)
            case .string(let value): out.appendOSCString(value)
            case .blob(let bytes):
                out.appendBigEndian(UInt32(bytes.count))
                out += bytes
                out.padToFour()
            }
        }
        return out
    }

    public init(decoding bytes: [UInt8]) throws(OSCError) {
        var reader = OSCReader(bytes)
        address = try reader.string()
        guard address.hasPrefix("/") else { throw .malformed("address must start with /") }
        let tags = try reader.string()
        guard tags.hasPrefix(",") else { throw .malformed("missing type tag") }
        arguments = []
        for tag in tags.utf8.dropFirst() {
            switch tag {
            case UInt8(ascii: "i"): arguments.append(.int(Int32(bitPattern: try reader.uint32())))
            case UInt8(ascii: "f"): arguments.append(.float(Float(bitPattern: try reader.uint32())))
            case UInt8(ascii: "s"): arguments.append(.string(try reader.string()))
            case UInt8(ascii: "b"): arguments.append(.blob(try reader.blob()))
            default: throw .malformed("unsupported type tag \(Character(UnicodeScalar(tag)))")
            }
        }
    }
}

/// A received OSC packet: a message or a bundle of packets.
public enum OSCPacket: Equatable, Sendable {
    case message(OSCMessage)
    case bundle([OSCPacket])

    public init(decoding bytes: [UInt8]) throws(OSCError) {
        guard bytes.starts(with: Array("#bundle\0".utf8)) else {
            self = .message(try OSCMessage(decoding: bytes))
            return
        }
        var reader = OSCReader(bytes)
        _ = try reader.string()   // "#bundle"
        _ = try reader.uint32()   // time tag, high
        _ = try reader.uint32()   // time tag, low
        var elements: [OSCPacket] = []
        while !reader.isAtEnd {
            let size = Int(try reader.uint32())
            elements.append(try OSCPacket(decoding: try reader.bytes(size)))
        }
        self = .bundle(elements)
    }

    /// Every message in the packet, in order, with bundles flattened.
    public var messages: [OSCMessage] {
        switch self {
        case .message(let message): [message]
        case .bundle(let elements): elements.flatMap(\.messages)
        }
    }
}

public enum OSCError: Error, Equatable {
    case truncated
    case malformed(String)
}

// MARK: - Encoding and decoding helpers

private extension Array where Element == UInt8 {
    mutating func appendOSCString(_ string: String) {
        append(contentsOf: string.utf8)
        append(0)
        padToFour()
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }

    mutating func padToFour() {
        while count % 4 != 0 { append(0) }
    }
}

private struct OSCReader {
    let bytes: [UInt8]
    var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func bytes(_ count: Int) throws(OSCError) -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw .truncated }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func uint32() throws(OSCError) -> UInt32 {
        let b = try bytes(4)
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }

    mutating func string() throws(OSCError) -> String {
        guard let end = bytes[offset...].firstIndex(of: 0) else { throw .truncated }
        let value = String(decoding: bytes[offset..<end], as: UTF8.self)
        let padded = (end - offset + 1 + 3) & ~3
        guard offset + padded <= bytes.count else { throw .truncated }
        offset += padded
        return value
    }

    mutating func blob() throws(OSCError) -> [UInt8] {
        let count = Int(try uint32())
        let value = try bytes(count)
        offset += (4 - count % 4) % 4
        guard offset <= bytes.count else { throw .truncated }
        return value
    }
}

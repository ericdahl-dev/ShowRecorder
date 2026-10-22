/// One OSC argument. Strings can be written as literals: `OSCMessage("/a", ["text"])`.
public enum OSCArgument: Equatable, Sendable, ExpressibleByStringLiteral {
    case int(Int32)
    case float(Float)
    case string(String)

    public init(stringLiteral value: String) { self = .string(value) }

    var typeTag: UInt8 {
        switch self {
        case .int: UInt8(ascii: "i")
        case .float: UInt8(ascii: "f")
        case .string: UInt8(ascii: "s")
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
            default: throw .malformed("unsupported type tag \(Character(UnicodeScalar(tag)))")
            }
        }
    }
}

/// A received OSC packet: one message. Bundles are refused (#886): neither the XR18 nor the X32 sends them, and
/// decoding bundles nested in bundles could crash the app on a spoofed packet.
public enum OSCPacket: Equatable, Sendable {
    case message(OSCMessage)

    public init(decoding bytes: [UInt8]) throws(OSCError) {
        guard !bytes.starts(with: Array("#bundle\0".utf8)) else { throw .malformed("bundles aren't supported") }
        self = .message(try OSCMessage(decoding: bytes))
    }

    /// The packet's messages, in order.
    public var messages: [OSCMessage] {
        switch self {
        case .message(let message): [message]
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
}

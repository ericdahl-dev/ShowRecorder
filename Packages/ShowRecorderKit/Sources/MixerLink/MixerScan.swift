import Foundation
import OSC

/// The addresses Find mixers asks (#289): every host on the device's own IPv4 network, except the device, and at
/// most a /22.
public struct ScanRange: Equatable, Sendable {
    public let hosts: [String]

    /// - Parameters:
    ///   - address: the device's own IPv4 address, such as "192.168.1.23".
    ///   - netmask: its network's mask, such as "255.255.255.0".
    public init?(address: String, netmask: String) {
        guard let own = Self.parse(address), let netmask = Self.parse(netmask) else { return nil }
        // A network bigger than a /22 is scanned only in the /22 around the device, to keep it to a few seconds.
        let mask = netmask | Self.widestScanMask
        let network = own & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return nil }
        hosts = ((network + 1)..<broadcast).filter { $0 != own }.map(Self.format)
    }

    /// A /22: at most 1,022 addresses.
    static let widestScanMask: UInt32 = 0xFFFF_FC00

    static func parse(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return nil }
        return parts.reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func format(_ value: UInt32) -> String {
        (0..<4).reversed().map { String(value >> ($0 * 8) & 0xFF) }.joined(separator: ".")
    }
}

/// A mixer that answered Find mixers.
public struct FoundMixer: Equatable, Sendable {
    /// Its IPv4 address, as the Mixer Link takes it.
    public var host: String
    public var identity: MixerIdentity

    public init(host: String, identity: MixerIdentity) {
        self.host = host
        self.identity = identity
    }
}

/// Asks many addresses for `/xinfo` at once and lists the X-Air and X32 mixers that answer (#289, #199). Unicast only,
/// from one UDP socket, paced, then listens for `timeout` after the last query. It sends nothing but `/xinfo`.
public enum MixerScanner {
    /// The X-Air's port and the X32's: each address is asked on both.
    public static let defaultPorts: [UInt16] = [10024, 10023]

    public static func scan(hosts: [String], ports: [UInt16] = defaultPorts, timeout: Duration = .seconds(1)) async -> [FoundMixer] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: scanBlocking(hosts: hosts, ports: ports, timeout: timeout))
            }
        }
    }

    private static func scanBlocking(hosts: [String], ports: [UInt16], timeout: Duration) -> [FoundMixer] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let query = OSCMessage("/xinfo").encoded()
        var found: [String: MixerIdentity] = [:]
        // Paced, about 2 ms an address: each query to a new address also makes the system look the address up (ARP),
        // and a burst of a thousand lookups is dropped on Wi-Fi, so a cold scan finds nothing (seen on the XR18).
        for host in hosts {
            for port in ports { send(query, to: host, port: port, on: fd) }
            collect(on: fd, into: &found, until: ContinuousClock.now + .milliseconds(2))
        }
        collect(on: fd, into: &found, until: ContinuousClock.now + timeout)
        return found
            .map { FoundMixer(host: $0.key, identity: $0.value) }
            .sorted { (ScanRange.parse($0.host) ?? 0) < (ScanRange.parse($1.host) ?? 0) }
    }

    private static func send(_ query: [UInt8], to host: String, port: UInt16, on fd: Int32) {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return }
        // A full send buffer (EAGAIN) waits until it can send, or the query would be lost. Any other failure (no
        // route, the host is down) just means that address won't answer.
        while true {
            let sent = query.withUnsafeBytes { bytes in
                withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent < 0, errno == EAGAIN else { return }
            var writable = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&writable, 1, 50) > 0 else { return }
        }
    }

    /// Reads `/xinfo` replies until `deadline`, keyed by the address they came from.
    private static func collect(on fd: Int32, into found: inout [String: MixerIdentity], until deadline: ContinuousClock.Instant) {
        var buffer = [UInt8](repeating: 0, count: 2048)
        while ContinuousClock.now < deadline {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            guard count > 0 else {
                usleep(2_000)
                continue
            }
            guard let identity = identity(in: Array(buffer[0..<count])) else { continue }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &text, socklen_t(INET_ADDRSTRLEN))
            found[String(cString: text)] = identity
        }
    }

    /// An `/xinfo` reply: the Mixer's IP, network name, model and firmware.
    static func identity(in data: [UInt8]) -> MixerIdentity? {
        guard let message = (try? OSCPacket(decoding: data))?.messages.first(where: { $0.address == "/xinfo" }) else { return nil }
        let strings = message.arguments.compactMap { if case .string(let value) = $0 { value } else { nil } }
        guard strings.count >= 4 else { return nil }
        return MixerIdentity(networkName: strings[1], model: strings[2], firmware: strings[3])
    }
}

extension ScanRange {
    /// The range around the device's own IPv4 network: Wi-Fi or Ethernet, the first that is up and not loopback.
    /// Nil with no such network (Wi-Fi off, say).
    public static func currentNetwork() -> ScanRange? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [(name: String, range: ScanRange)] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let netmask = entry.pointee.ifa_netmask,
                  let range = ScanRange(address: text(address), netmask: text(netmask)) else { continue }
            candidates.append((String(cString: entry.pointee.ifa_name), range))
        }
        // en0 is Wi-Fi on an iPhone and usually the built-in network on a Mac; other "en" interfaces are Ethernet.
        return (candidates.first { $0.name == "en0" } ?? candidates.first { $0.name.hasPrefix("en") })?.range
    }

    private static func text(_ address: UnsafeMutablePointer<sockaddr>) -> String {
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            var addr = $0.pointee.sin_addr
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr, &text, socklen_t(INET_ADDRSTRLEN))
            return String(cString: text)
        }
    }
}

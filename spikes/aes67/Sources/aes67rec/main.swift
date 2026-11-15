// aes67rec: join one AES67 multicast stream from an SDP and record one 24-bit WAV per channel.
//   aes67rec --sdp stream.sdp --out DIR [--iface 127.0.0.1] [--seconds N] [--window-ms 20] [--stats out.json]
// Stops after --seconds, or 2 s after the last packet once packets have started.
import AES67Core
import Darwin
import Foundation

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}
func die(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }

guard let sdpPath = arg("--sdp"), let outDir = arg("--out") else {
    die("usage: aes67rec --sdp FILE --out DIR [--iface ADDR] [--seconds N] [--window-ms MS] [--stats FILE]")
}
let sdp: StreamDescription
do { sdp = try parseSDP(try String(contentsOfFile: sdpPath, encoding: .utf8)) } catch { die("SDP: \(error)") }
let iface = arg("--iface") ?? "127.0.0.1"
let maxSeconds = Double(arg("--seconds") ?? "0") ?? 0
let windowMs = Double(arg("--window-ms") ?? "20") ?? 20
print("stream \(sdp.group):\(sdp.port) PT \(sdp.payloadType) \(sdp.encoding)/\(sdp.sampleRate)/\(sdp.channels) ptime \(sdp.ptimeMs ?? 0) ms refclk \(sdp.refClock ?? "-") mediaclk \(sdp.mediaClock ?? "-")")

// MARK: socket
let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
guard fd >= 0 else { die("socket: \(errno)") }
var one: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, socklen_t(MemoryLayout<Int32>.size))
setsockopt(fd, SOL_SOCKET, SO_TIMESTAMP, &one, socklen_t(MemoryLayout<Int32>.size))
// Kernel arrival time on the monotonic clock (mach_absolute_time), not NTP-slewed like the wall clock.
setsockopt(fd, SOL_SOCKET, 0x0800 /* SO_TIMESTAMP_MONOTONIC */, &one, socklen_t(MemoryLayout<Int32>.size))
var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func machSeconds(_ t: UInt64) -> Double { Double(t) * Double(timebase.numer) / Double(timebase.denom) / 1e9 }
var rcvbuf: Int32 = 4 << 20
if setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, socklen_t(MemoryLayout<Int32>.size)) != 0 {
    rcvbuf = 1 << 20
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, socklen_t(MemoryLayout<Int32>.size))
}
var got: Int32 = 0
var gotLen = socklen_t(MemoryLayout<Int32>.size)
getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &got, &gotLen)
var tv = timeval(tv_sec: 0, tv_usec: 100_000)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

var bindAddr = sockaddr_in()
bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
bindAddr.sin_family = sa_family_t(AF_INET)
bindAddr.sin_port = sdp.port.bigEndian
bindAddr.sin_addr.s_addr = inet_addr(sdp.group) // bind to the group so other groups on the port are not delivered
let bound = withUnsafePointer(to: &bindAddr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
guard bound == 0 else { die("bind: \(String(cString: strerror(errno)))") }
// A unicast c= address (e.g. 127.0.0.1 for the ffmpeg cross-check) is only bound, not joined.
let first = UInt32(bigEndian: inet_addr(sdp.group)) >> 28
if first == 0xE {
    var mreq = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr(sdp.group)), imr_interface: in_addr(s_addr: inet_addr(iface)))
    guard setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size)) == 0 else {
        die("IP_ADD_MEMBERSHIP: \(String(cString: strerror(errno)))")
    }
    print("joined \(sdp.group) on \(iface), SO_RCVBUF \(got) bytes")
} else {
    print("unicast \(sdp.group):\(sdp.port), SO_RCVBUF \(got) bytes")
}

// MARK: recording state
let bytesPerFrame = sdp.channels * sdp.bytesPerSample
let wavs: WAVSet
do {
    wavs = try WAVSet(directory: URL(fileURLWithPath: outDir), prefix: "aes67", channels: sdp.channels,
                      sampleRate: sdp.sampleRate, inBytesPerSample: sdp.bytesPerSample)
} catch { die("WAV: \(error)") }
let reasm = Reassembler(bytesPerFrame: bytesPerFrame,
                        windowFrames: Int(windowMs / 1000 * Double(sdp.sampleRate)), sink: wavs)
var seqStats = SequenceStats()
var timing = TimingStats(sampleRate: Double(sdp.sampleRate))
var timingWallClock = TimingStats(sampleRate: Double(sdp.sampleRate)) // only for its drift figure
var monotonicStamps = 0
var tsUnwrap = Unwrapper(bits: 32)
var wrongPT = 0, badPackets = 0, otherSSRC = 0
var ssrc: UInt32?
var packetFrames = Set<Int>()
var userTimingMaxLag = 0.0 // kernel timestamp to our read, worst case

func now() -> Double { var t = timespec(); clock_gettime(CLOCK_REALTIME, &t); return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9 }
func cpuSeconds() -> Double {
    var u = rusage(); getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6 + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
}

var running = true
signal(SIGINT) { _ in running = false }
signal(SIGTERM) { _ in running = false }

var buf = [UInt8](repeating: 0, count: 9000)
var control = [UInt8](repeating: 0, count: 256)
var firstPacketAt: Double?
var lastPacketAt: Double?
var cpuAtFirst = 0.0
var nextReport = 0.0
let started = now()

while running {
    var iov = iovec()
    var msg = msghdr()
    let n: Int = buf.withUnsafeMutableBytes { b in
        control.withUnsafeMutableBytes { c in
            iov.iov_base = b.baseAddress
            iov.iov_len = b.count
            return withUnsafeMutablePointer(to: &iov) { iovp in
                msg.msg_iov = iovp
                msg.msg_iovlen = 1
                msg.msg_control = c.baseAddress
                msg.msg_controllen = socklen_t(c.count)
                return recvmsg(fd, &msg, 0)
            }
        }
    }
    let t = now()
    if n < 0 {
        if errno != EAGAIN && errno != EINTR { die("recvmsg: \(String(cString: strerror(errno)))") }
    } else {
        // Kernel arrival time from SO_TIMESTAMP (Darwin aligns cmsg data to 4 bytes).
        var arrival = t
        var arrivalMono = machSeconds(mach_absolute_time())
        var hadMono = false
        control.withUnsafeBytes { c in
            var off = 0
            while off + 12 <= Int(msg.msg_controllen) {
                let len = Int(c.loadUnaligned(fromByteOffset: off, as: UInt32.self))
                let level = c.loadUnaligned(fromByteOffset: off + 4, as: Int32.self)
                let type = c.loadUnaligned(fromByteOffset: off + 8, as: Int32.self)
                if level == SOL_SOCKET && type == SCM_TIMESTAMP {
                    let tv = c.loadUnaligned(fromByteOffset: off + 12, as: timeval.self)
                    arrival = Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
                } else if level == SOL_SOCKET && type == 0x04 /* SCM_TIMESTAMP_MONOTONIC */ {
                    arrivalMono = machSeconds(c.loadUnaligned(fromByteOffset: off + 12, as: UInt64.self))
                    hadMono = true
                }
                guard len > 0 else { break }
                off += (len + 3) & ~3
            }
        }
        userTimingMaxLag = max(userTimingMaxLag, t - arrival)
        buf.withUnsafeBytes { b in
            let d = UnsafeRawBufferPointer(rebasing: b[0..<n])
            guard let h = parseRTP(d) else { badPackets += 1; return }
            guard h.payloadType == sdp.payloadType else { wrongPT += 1; return }
            if ssrc == nil { ssrc = h.ssrc } else if h.ssrc != ssrc { otherSSRC += 1; return }
            if firstPacketAt == nil { firstPacketAt = arrival; cpuAtFirst = cpuSeconds(); nextReport = t + 10 }
            lastPacketAt = t
            let before = seqStats.highest
            let wasFirst = seqStats.first == nil
            seqStats.record(h.sequence)
            let inOrder = wasFirst || seqStats.highest > before
            let ets = tsUnwrap.extend(UInt64(h.timestamp))
            timing.record(arrival: arrivalMono, timestamp: ets, inOrder: inOrder)
            timingWallClock.record(arrival: arrival, timestamp: ets, inOrder: inOrder)
            if hadMono { monotonicStamps += 1 }
            packetFrames.insert(h.payload.count / bytesPerFrame)
            reasm.insert(timestamp: ets, payload: buf[h.payload])
        }
    }
    if let f = firstPacketAt {
        if t >= nextReport {
            let wall = t - f
            print(String(format: "%6.0f s  pkts %d  lost %lld  reord %d  dup %d  gaps %d  jitter %.1f µs  cpu %.2f%%",
                         wall, seqStats.received, seqStats.lost, seqStats.reordered, seqStats.duplicates, reasm.gapEvents,
                         timing.rfc3550Jitter / Double(sdp.sampleRate) * 1e6, (cpuSeconds() - cpuAtFirst) / wall * 100))
            fflush(stdout)
            nextReport += 10
        }
        if maxSeconds > 0 && t - f >= maxSeconds { break }
        if let l = lastPacketAt, t - l > 2 { break }
    } else if maxSeconds > 0 && t - started > maxSeconds + 30 {
        die("no packets")
    }
}

reasm.finish()
let end = lastPacketAt ?? now()
let wall = end - (firstPacketAt ?? end)
let cpu = cpuSeconds() - cpuAtFirst
do { try wavs.close() } catch { die("close: \(error)") }
var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
let pct = [0.5, 0.99, 0.999, 1.0]
let spread = timing.spreadMicroseconds(percentiles: pct)
let report: [String: Any] = [
    "seconds": wall,
    "channels": sdp.channels,
    "packetFrames": packetFrames.sorted(),
    "received": seqStats.received,
    "expected": seqStats.expected,
    "lost": seqStats.lost,
    "duplicates": seqStats.duplicates,
    "reordered": seqStats.reordered,
    "maxReorderDepth": seqStats.maxReorderDepth,
    "gapEvents": reasm.gapEvents,
    "gapFrames": reasm.gapFrames,
    "lateDropped": reasm.lateDropped,
    "pendingDuplicates": reasm.pendingDuplicates,
    "maxPendingPackets": reasm.maxPending,
    "framesWritten": wavs.framesWritten,
    "wrongPayloadType": wrongPT, "badPackets": badPackets, "otherSSRC": otherSSRC,
    "rfc3550JitterUsFinal": timing.rfc3550Jitter / Double(sdp.sampleRate) * 1e6,
    "rfc3550JitterUsMax": timing.maxRfc3550Jitter / Double(sdp.sampleRate) * 1e6,
    "transitSpreadUs_p50_p99_p999_max": spread,
    "maxInterArrivalMs": timing.maxInterArrival * 1000,
    "driftPPM": timing.driftPPM,
    "driftPPMAgainstWallClock": timingWallClock.driftPPM,
    "kernelMonotonicStamps": monotonicStamps,
    "kernelToUserMaxLagMs": userTimingMaxLag * 1000,
    "cpuSeconds": cpu,
    "cpuPercentOfOneCore": wall > 0 ? cpu / wall * 100 : 0,
    "maxRSSMB": Double(ru.ru_maxrss) / 1_048_576,
    "rcvbufBytes": got,
    "clean": seqStats.lost == 0 && reasm.gapEvents == 0 && reasm.lateDropped == 0,
]
let json = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(data: json, encoding: .utf8)!)
if let p = arg("--stats") { try? json.write(to: URL(fileURLWithPath: p)) }

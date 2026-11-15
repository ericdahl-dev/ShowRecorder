/// Packet counts by RTP sequence number: loss, duplicates and reordering.
public struct SequenceStats {
    private var unwrap = Unwrapper(bits: 16)
    public private(set) var first: Int64?
    public private(set) var highest: Int64 = 0
    public private(set) var received = 0
    public private(set) var duplicates = 0
    /// Packets that arrived after one with a higher sequence number.
    public private(set) var reordered = 0
    /// Largest distance (in packets) a reordered packet arrived behind the highest one.
    public private(set) var maxReorderDepth: Int64 = 0
    private var seen = Set<Int64>()

    public init() {}

    public mutating func record(_ seq: UInt16) {
        let e = unwrap.extend(UInt64(seq))
        received += 1
        if first == nil { first = e; highest = e }
        if seen.contains(e) {
            duplicates += 1
            return
        }
        seen.insert(e)
        if e < highest {
            reordered += 1
            maxReorderDepth = max(maxReorderDepth, highest - e)
        } else {
            highest = e
        }
        if seen.count > 8192 {
            let floor = highest - 4096
            seen = seen.filter { $0 >= floor }
        }
    }

    public var unique: Int { received - duplicates }
    public var expected: Int64 { first.map { highest - $0 + 1 } ?? 0 }
    public var lost: Int64 { expected - Int64(unique) }
}

/// Arrival timing. `transit` = arrival time (in samples) minus RTP timestamp; its spread is the jitter a
/// receive buffer has to absorb, and its slope against time is the sender's clock drift against ours.
public struct TimingStats {
    public let sampleRate: Double
    public private(set) var packets = 0
    /// RFC 3550 interarrival jitter, in samples.
    public private(set) var rfc3550Jitter: Double = 0
    public private(set) var maxRfc3550Jitter: Double = 0
    private var lastTransit: Double?
    private var minTransit = Double.infinity
    private var maxTransit = -Double.infinity
    /// (elapsed arrival s, transit s) per packet.
    private var points: [(x: Double, y: Double)] = []
    // Least squares of transit (s) against arrival (s), for drift.
    private var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
    private var t0: Double?
    private var lastArrival: Double?
    public private(set) var maxInterArrival: Double = 0

    public init(sampleRate: Double) { self.sampleRate = sampleRate }

    /// `arrival` in seconds (any epoch), `timestamp` the extended RTP timestamp.
    public mutating func record(arrival: Double, timestamp: Int64, inOrder: Bool) {
        packets += 1
        if t0 == nil { t0 = arrival }
        let transit = arrival * sampleRate - Double(timestamp)
        if inOrder, let last = lastTransit {
            let d = abs(transit - last)
            rfc3550Jitter += (d - rfc3550Jitter) / 16
            maxRfc3550Jitter = max(maxRfc3550Jitter, rfc3550Jitter)
        }
        if inOrder { lastTransit = transit }
        if let la = lastArrival { maxInterArrival = max(maxInterArrival, arrival - la) }
        lastArrival = arrival
        minTransit = min(minTransit, transit)
        maxTransit = max(maxTransit, transit)
        let x = arrival - t0!, y = transit / sampleRate
        points.append((x, y))
        n += 1; sx += x; sy += y; sxx += x * x; sxy += x * y
    }

    /// Drift of the sender's sample clock against the arrival clock, in parts per million.
    public var driftPPM: Double {
        let den = n * sxx - sx * sx
        guard n > 2, den != 0 else { return 0 }
        return (n * sxy - sx * sy) / den * 1e6
    }

    /// Transit spread in microseconds after removing drift: percentiles of (transit - its lowest value).
    /// The top percentile is about how deep a receive buffer has to be to never run dry.
    public func spreadMicroseconds(percentiles: [Double]) -> [Double] {
        guard !points.isEmpty else { return percentiles.map { _ in 0 } }
        let slope = driftPPM / 1e6
        let detrended = points.map { $0.y - slope * $0.x }
        let floor = detrended.min()!
        let sorted = detrended.map { ($0 - floor) * 1e6 }.sorted()
        return percentiles.map { p in sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))] }
    }

    public var rawSpreadMicroseconds: Double { (maxTransit - minTransit) / sampleRate * 1e6 }
}

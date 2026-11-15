/// Where reassembled audio goes: interleaved big-endian payload bytes, or a run of silence for a gap.
public protocol FrameSink: AnyObject {
    func write(payload: ArraySlice<UInt8>, frames: Int)
    func writeSilence(frames: Int)
}

/// Puts packets back in order by RTP timestamp and writes them out, so sample N of the file is always
/// RTP timestamp origin+N. A packet waits up to `windowFrames` for the ones before it; past that the
/// missing span is written as silence and counted as a gap. A packet for a span already written (a late
/// arrival after its gap was filled, or a duplicate) is dropped and counted.
public final class Reassembler {
    public let bytesPerFrame: Int
    public let windowFrames: Int
    public private(set) var origin: Int64?
    /// Next frame offset (from `origin`) to write.
    public private(set) var cursor: Int64 = 0
    private var pending: [Int64: [UInt8]] = [:]
    private var newestEnd: Int64 = 0
    private let sink: FrameSink

    public private(set) var gapEvents = 0
    public private(set) var gapFrames: Int64 = 0
    public private(set) var lateDropped = 0
    public private(set) var pendingDuplicates = 0
    public private(set) var framesWritten: Int64 = 0
    public private(set) var maxPending = 0

    public init(bytesPerFrame: Int, windowFrames: Int, sink: FrameSink) {
        self.bytesPerFrame = bytesPerFrame
        self.windowFrames = windowFrames
        self.sink = sink
    }

    /// `timestamp` is the extended (unwrapped) RTP timestamp.
    public func insert(timestamp: Int64, payload: ArraySlice<UInt8>) {
        let frames = payload.count / bytesPerFrame
        guard frames > 0 else { return }
        if origin == nil { origin = timestamp }
        let offset = timestamp - origin!
        if offset < cursor {
            lateDropped += 1
            return
        }
        if pending[offset] != nil {
            pendingDuplicates += 1
            return
        }
        pending[offset] = Array(payload.prefix(frames * bytesPerFrame))
        newestEnd = max(newestEnd, offset + Int64(frames))
        maxPending = max(maxPending, pending.count)
        drain(force: false)
    }

    /// Writes everything still waiting, filling holes with silence. Call at the end of a recording.
    public func finish() { drain(force: true) }

    private func drain(force: Bool) {
        while !pending.isEmpty {
            if let p = pending.removeValue(forKey: cursor) {
                let frames = p.count / bytesPerFrame
                sink.write(payload: p[...], frames: frames)
                cursor += Int64(frames)
                framesWritten += Int64(frames)
                continue
            }
            guard force || newestEnd - cursor > Int64(windowFrames) else { return }
            let next = pending.keys.min()!
            let gap = next - cursor
            sink.writeSilence(frames: Int(gap))
            gapEvents += 1
            gapFrames += gap
            framesWritten += gap
            cursor = next
        }
    }
}

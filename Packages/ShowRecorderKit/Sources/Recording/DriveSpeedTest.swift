import AudioIO
import BroadcastWave
import Foundation
import Synchronization

/// How many channels a Drive can reliably record (#807, Debug only). It writes Stems the way a Take does: the real
/// `TakeWriter` (same file format, same header commit cadence) drains a ring that a plain producer thread fills at
/// real-time pace. No audio thread and no interface are involved.
public enum DriveSpeedTest {
    /// What one step found.
    public struct StepResult: Equatable, Sendable {
        public var channels: Int
        public var sampleRate: Int
        /// The Drive kept up: no audio dropped, no stall past the limit, no growing backlog, no failed or hung write, and
        /// the step ran to its end.
        public var reliable: Bool
        /// The longest stretch the writer made no progress while audio was waiting. A real Take marks a Gap past its limit.
        public var worstStall: Duration
        /// The most audio that sat waiting for the writer. A Drive slower than real time shows here long before the ring
        /// overflows; half the ring (2 s) counts as falling behind.
        public var peakBacklog: Duration
        public var fellBehind: Bool
        public var framesWritten: Int
        public var droppedFrames: Int
        /// Audio bytes written per second over the step.
        public var bytesPerSecond: Double
        public var wasCanceled: Bool
    }

    static let scratchPrefix = ".ShowRecorder-speedtest-"
    private static let blockFrames = 100  // per second, so 10 ms blocks

    /// Writes `channels` Stems for `duration` into a scratch folder in `drive`, then removes it, even after a cancel.
    /// Blocks until done (the caller keeps it off the main actor); `isCancelled` is asked once per 10 ms block. Ends early
    /// on a failed write or a backlog of half the ring, since the answer is known.
    static func runStep(
        in drive: URL, channels: Int, sampleRate: Int, duration: Duration, stallLimit: Duration,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        drainTimeout: Duration = .seconds(10),
        makeStem: (URL, StemWriter.Info) throws -> any StemSink = { try StemWriter.open(url: $0, info: $1, resumingAt: nil) }
    ) throws -> StepResult {
        precondition(channels > 0, "a step needs a channel")
        let folder = drive.appending(path: scratchPrefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let info = StemWriter.Info(
            sampleRate: sampleRate, description: "Drive speed test", originator: "ShowRecorder", timeReference: 0,
            originationDate: Date())
        let stems = try (1...channels).map { try makeStem(folder.appending(path: "Ch \($0).wav"), info) }
        let ring = SampleRing(channelCount: channels, capacity: sampleRate * 4)
        let writer = TakeWriter(feed: CopyFeed(ring: ring, joinedAt: 0), stems: stems, commitInterval: sampleRate * 2)
        writer.start()

        let frames = sampleRate / blockFrames
        let buffers = (0..<channels).map { channel in
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            // Not silence, and different per channel: nothing a Drive could shortcut.
            for index in 0..<frames { buffer[index] = sinf(Float(index + channel * 7) * 0.05) * 0.25 }
            return buffer
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers = buffers.map { UnsafePointer($0) }

        let clock = ContinuousClock()
        let start = clock.now
        let blocks = Int(duration.inSeconds * Double(blockFrames))
        var lastConsumed = 0
        var lastProgress = start
        var worstStall = Duration.zero
        var canceled = false
        var peakBacklog = 0
        let backlogLimit = ring.capacity / 2
        var fellBehind = false
        pointers.withUnsafeBufferPointer { channelPointers in
            for block in 0..<blocks {
                if isCancelled() { canceled = true; break }
                if writer.hasFailed { break }
                ring.write(AudioBlock(channels: channelPointers.baseAddress!, channelCount: channels, frameCount: frames, hostTime: 0))
                Thread.sleep(until: Date(timeIntervalSinceNow: (start + .milliseconds((block + 1) * 10) - clock.now).inSeconds))
                let now = clock.now
                let consumed = ring.consumedFrames
                if consumed != lastConsumed || ring.availableFrames == 0 {
                    lastConsumed = consumed
                    lastProgress = now
                } else {
                    worstStall = max(worstStall, now - lastProgress)
                }
                let backlog = ring.availableFrames
                peakBacklog = max(peakBacklog, backlog)
                if backlog >= backlogLimit { fellBehind = true; break }
            }
        }
        // A stall still going when the loop ends counts too.
        if ring.availableFrames > 0 { worstStall = max(worstStall, clock.now - lastProgress) }
        // Already known to be unreliable (or canceled): don't wait long for the rest to drain.
        let known = canceled || fellBehind || writer.hasFailed
        writer.stop(timeout: known ? .seconds(1) : drainTimeout)
        let hung = writer.wasAbandoned && !known
        if hung { worstStall = max(worstStall, drainTimeout) }
        let elapsed = (clock.now - start).inSeconds
        let written = writer.framesWritten
        let dropped = ring.overflowedFrames.load(ordering: .relaxed)
        return StepResult(
            channels: channels, sampleRate: sampleRate,
            reliable: !canceled && !fellBehind && !hung && dropped == 0 && worstStall < stallLimit && !writer.hasFailed,
            worstStall: worstStall, peakBacklog: .seconds(Double(peakBacklog) / Double(sampleRate)), fellBehind: fellBehind,
            framesWritten: written, droppedFrames: dropped,
            bytesPerSecond: elapsed > 0 ? Double(written * channels * 3) / elapsed : 0, wasCanceled: canceled)
    }
}

private extension Duration {
    var inSeconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

import AudioIO
import Darwin
import Synchronization

/// One Copy's feed from the real-time thread: its ring and the Take frame it joined at.
final class CopyFeed: Sendable {
    let ring: SampleRing
    /// This Copy's bit in Capture's masks; -1 for a feed no Capture owns.
    fileprivate let slot: Int
    /// The Take frame this Copy starts at: 0 for a Copy there from the start, later for one that joined
    /// mid-Take, -1 until the real-time thread has set it.
    private let joinFrame = Atomic<Int>(-1)

    fileprivate init(ring: SampleRing, slot: Int) {
        self.ring = ring
        self.slot = slot
    }

    /// A feed no Capture owns, already joined at `joinedAt`, for driving a writer by hand.
    convenience init(ring: SampleRing, joinedAt: Int) {
        self.init(ring: ring, slot: -1)
        joinFrame.store(joinedAt, ordering: .releasing)
    }

    /// The Take frame this Copy starts at, or nil until the real-time thread has said.
    var joinedAt: Int? {
        let frame = joinFrame.load(ordering: .acquiring)
        return frame < 0 ? nil : frame
    }

    /// Waits until the real-time thread says which Take frame this Copy starts at, calling `pause` between looks.
    /// Returns nil if `running` turns false first.
    func waitForJoin(while running: () -> Bool, pause: () -> Void) -> Int? {
        while true {
            if let joinedAt { return joinedAt }
            if !running() { return nil }
            pause()
        }
    }

    /// Empties the ring and says which Take frame this Copy starts at: nil until the real-time thread picks one.
    fileprivate func reset(joinedAt: Int?) {
        ring.discardAll()
        joinFrame.store(joinedAt ?? -1, ordering: .releasing)
    }

    /// Real-time safe: this Copy starts at Take frame `frame`.
    @inline(__always) fileprivate func markJoined(at frame: Int) {
        joinFrame.store(frame, ordering: .releasing)
    }
}

/// Everything the real-time callback touches, allocated when the recorder is Armed.
final class Capture: Sendable {
    let meters: PeakMeters
    /// The last seconds of every channel while Armed, for Pre-roll. Nil when Pre-roll is off.
    let preRoll: PreRollBuffer?
    /// One feed per Copy: the Device, then the Drive.
    let feeds: [CopyFeed]
    /// The feeds' rings, slot for slot, for the real-time thread.
    private let rings: [SampleRing]
    /// Which Copies are being captured, one bit per ring (bit 0 the Device, bit 1 the Drive); 0 when not recording.
    private let capturing = Atomic<Int>(0)
    /// Copies waiting for the real-time thread to start feeding them, one bit per ring.
    private let joinRequests = Atomic<Int>(0)
    /// Copies no longer fed, one bit per ring: masks `capturing`, so a stop that lands after the real-time thread
    /// read the join requests still keeps the Copy unfed (#544).
    private let stoppedFeeds = Atomic<Int>(0)
    /// Frames delivered since the Take started: the Take's sample timeline. A Take with Pre-roll starts
    /// it at the Pre-roll's length, so frame 0 is the first Pre-roll sample.
    private let takeFrames = Atomic<Int>(0)
    /// For a Take with Pre-roll: where the Take's first live frame sits in the Pre-roll buffer's own count,
    /// set by the real-time thread at the block that starts feeding the Copies. -2 until then, -1 when the
    /// Take has no Pre-roll.
    let preRollStart = Atomic<Int>(-1)
    /// Host-clock ticks per frame, and the host time the next block should start at: a block that starts much later
    /// means input stopped (an interruption), and the missing stretch becomes a Dropout (#317). 0 until the first block.
    private let hostTicksPerFrame: Double
    private let expectedHostTime = Atomic<UInt64>(0)
    /// Where the Take's timeline stands at the join block, relative to the Pre-roll buffer's own count: the Take's frame at
    /// that block is this plus the block's start in the buffer (#915). `Int.min` when the Take has none: its frame is then
    /// the preset one. Set when a Take starts, read by the real-time thread; a store and a load, nothing else.
    private let joinOffset = Atomic<Int>(Int.min)
    /// The Pre-roll length the Capture was made for: zero keeps the buffer only for a Take that starts late.
    let preRollSeconds: Double
    /// Frames in a second at the Capture's rate: the margin the Pre-roll buffer keeps free of reads.
    let framesPerSecond: Int
    /// The host clock now, read when a Take starts (never on the real-time thread).
    private let hostClock: @Sendable () -> UInt64
    /// A gap shorter than this (frames) is timing jitter, not lost input.
    private let gapThreshold: Int
    /// Tests only: runs on the real-time thread after a join block sets the join frames, before the Copies are added to
    /// `capturing` (#544, #945). Nil otherwise.
    private let afterJoinRead: (@Sendable () -> Void)?
    /// The host clock's ticks per second on this machine.
    static let machTicksPerSecond: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return 1e9 * Double(info.denom) / Double(info.numer)
    }()

    var channelCount: Int { rings[0].channelCount }

    /// Frames the Copy that lost the most has dropped because its ring was full.
    var maxOverflowedFrames: Int { rings.map { $0.overflowedFrames.load(ordering: .relaxed) }.max() ?? 0 }

    /// Frames captured but not yet taken by their writer, for the Copy furthest behind.
    var maxBufferedFrames: Int { rings.map(\.availableFrames).max() ?? 0 }

    /// Whether every Copy's writer has taken all that was captured for it.
    var isDrained: Bool { rings.allSatisfy { $0.availableFrames == 0 } }

    /// - Parameter preRollSeconds: how much audio to keep before a Take starts; the buffer holds a second
    ///   more, so a read of that length isn't cut short by the writer overwriting its oldest frames.
    /// - Parameter startHeadroomSeconds: room in the buffer for a Take that starts late (#915): the time between the press
    ///   and the first live block, while the Drive's files are made. With it the buffer exists even when Pre-roll is off. It is
    ///   allocated here, at Arm, never when a Take starts.
    init(channelCount: Int, sampleRate: Double, preRollSeconds: Double = 0, startHeadroomSeconds: Double = 0,
         hostTicksPerSecond: Double = Capture.machTicksPerSecond, hostClock: @escaping @Sendable () -> UInt64 = { mach_absolute_time() },
         afterJoinRead: (@Sendable () -> Void)? = nil) {
        self.hostClock = hostClock
        self.afterJoinRead = afterJoinRead
        self.preRollSeconds = preRollSeconds
        framesPerSecond = Int(max(sampleRate, 1))
        hostTicksPerFrame = hostTicksPerSecond / max(sampleRate, 1)
        gapThreshold = Int(max(sampleRate, 1) * 0.05)
        meters = PeakMeters(channelCount: channelCount)
        preRoll = preRollSeconds > 0 || startHeadroomSeconds > 0
            ? PreRollBuffer(channelCount: channelCount, capacity: Int((preRollSeconds + startHeadroomSeconds + 1) * max(sampleRate, 1)))
            : nil
        // Four seconds of headroom for each writer thread.
        let feeds = (0..<2).map { CopyFeed(ring: SampleRing(channelCount: channelCount, capacity: Int(max(sampleRate, 1) * 4)), slot: $0) }
        self.feeds = feeds
        rings = feeds.map(\.ring)
    }

    /// Empties `feed`'s ring and says which Take frame its Copy starts at: nil until the real-time thread picks one.
    func begin(_ feed: CopyFeed, joinedAt: Int?) {
        precondition(feed.slot >= 0, "a feed this Capture doesn't own")
        feed.reset(joinedAt: joinedAt)
    }

    /// Starts feeding the Copies' rings. With `preRollFrames`, the Take's timeline starts at that many
    /// frames and the Copies start at the next block boundary, which the real-time thread notes in
    /// `preRollStart` so the Pre-roll and the live audio join without a lost or repeated sample.
    /// - Parameter pressPosition: the Pre-roll buffer's count of frames at the press (#915). A Take that starts late then still
    ///   begins `preRollFrames` before the press: at the join block its timeline stands at `preRollFrames` plus the frames
    ///   that came in since the press, and the head reaches back to the press minus Pre-roll.
    func startCapturing(copies: Int, preRollFrames: Int = 0, pressPosition: Int? = nil) {
        let mask = (1 << min(copies, rings.count)) - 1
        takeFrames.store(preRollFrames, ordering: .releasing)
        // Not on the real-time thread: this runs when a Take starts. Without a position (or a buffer) the preset stands.
        let offset: Int = if preRoll != nil, let pressPosition { preRollFrames - pressPosition } else { Int.min }
        joinOffset.store(offset, ordering: .releasing)
        // The Take starts at the press: input stopped before it is no part of the Take (#877). With input running, the
        // next block starts before the press, so this adds nothing.
        expectedHostTime.store(hostClock(), ordering: .relaxed)
        stoppedFeeds.store(0, ordering: .releasing)
        if preRollFrames > 0 || pressPosition != nil, preRoll != nil {
            preRollStart.store(-2, ordering: .releasing)
            capturing.store(0, ordering: .releasing)
            joinRequests.store(mask, ordering: .releasing)
        } else {
            preRollStart.store(-1, ordering: .releasing)
            capturing.store(mask, ordering: .releasing)
        }
    }

    /// Whether the Take has Pre-roll but the real-time thread hasn't yet fed it a first block.
    var awaitingFirstBlock: Bool { preRollStart.load(ordering: .acquiring) == -2 }

    /// Frames delivered since the Take started.
    var takeFrameCount: Int { takeFrames.load(ordering: .acquiring) }

    /// Brings a Copy into the running Take: empties its ring, forgets any join frame, then asks the real-time
    /// thread to start feeding it from its next block and to record the Take frame it starts at in `feed`.
    func attachMidTake(_ feed: CopyFeed) {
        precondition(feed.slot >= 0, "a feed this Capture doesn't own")
        feed.reset(joinedAt: nil)
        stoppedFeeds.bitwiseAnd(~(1 << feed.slot), ordering: .acquiringAndReleasing)
        joinRequests.bitwiseOr(1 << feed.slot, ordering: .acquiringAndReleasing)
    }

    /// Stops feeding one Copy's ring (its writer failed, or it retired).
    func stopFeeding(_ feed: CopyFeed) {
        precondition(feed.slot >= 0, "a feed this Capture doesn't own")
        // Stopped first: a join the real-time thread already read can't feed the Copy again (#544).
        stoppedFeeds.bitwiseOr(1 << feed.slot, ordering: .acquiringAndReleasing)
        // A join still waiting for its block would bring the Copy back (#872).
        joinRequests.bitwiseAnd(~(1 << feed.slot), ordering: .acquiringAndReleasing)
        capturing.bitwiseAnd(~(1 << feed.slot), ordering: .acquiringAndReleasing)
    }

    func stopCapturing() {
        // Requests first: the next block ORs any still pending back into `capturing` (#872).
        joinRequests.store(0, ordering: .releasing)
        capturing.store(0, ordering: .releasing)
    }

    /// Real-time: meter every block, and queue it for each Copy's writer while a Take is running.
    /// Real-time safe. If this block starts well after the last one ended, input was stopped (a call, Siri, another
    /// app took the session): the missing frames go into every Copy being recorded as a drop, which its writer turns
    /// into silence with a Dropout, and the Take's timeline moves on by as much, so the Stems keep their length (#317).
    private func noteInputGap(before block: AudioBlock, capturing mask: Int) {
        guard block.hostTime != 0 else { return }
        let expected = expectedHostTime.load(ordering: .relaxed)
        if expected != 0, mask != 0, block.hostTime > expected {
            let gap = Int((Double(block.hostTime - expected) / hostTicksPerFrame).rounded())
            if gap > gapThreshold {
                var copy = 0
                while copy < rings.count {
                    if mask & (1 << copy) != 0 { rings[copy].skip(frames: gap) }
                    copy += 1
                }
                takeFrames.add(gap, ordering: .relaxed)
            }
        }
        expectedHostTime.store(block.hostTime + UInt64((Double(block.frameCount) * hostTicksPerFrame).rounded()), ordering: .relaxed)
    }

    func receive(_ block: AudioBlock) {
        meters.record(block)
        preRoll?.write(block)
        // A read first, so a block with nothing waiting writes nothing shared; the claim is one exchange (#945).
        let requested = joinRequests.load(ordering: .relaxed) == 0 ? 0 : joinRequests.exchange(0, ordering: .acquiringAndReleasing)
        if requested != 0 {
            if preRollStart.load(ordering: .relaxed) == -2 {
                // The Pre-roll buffer already holds this block, so the live audio starts before it.
                let start = (preRoll?.totalWrittenFrames ?? block.frameCount) - block.frameCount
                // A Take that started late: its timeline reaches back to the press, not only to the first live block (#915).
                let offset = joinOffset.load(ordering: .acquiring)
                if offset != Int.min { takeFrames.store(offset + start, ordering: .releasing) }
                preRollStart.store(start, ordering: .releasing)
            }
            let frame = takeFrames.load(ordering: .relaxed)
            for copy in 0..<rings.count where requested & (1 << copy) != 0 {
                feeds[copy].markJoined(at: frame)
            }
            afterJoinRead?()
            capturing.bitwiseOr(requested, ordering: .acquiringAndReleasing)
            // A Copy stopped, or asked to join again, since its request was claimed: take it back out; a fresh request
            // is served at the next block at the right frame (#544, #945).
            let stale = (stoppedFeeds.load(ordering: .acquiring) | joinRequests.load(ordering: .acquiring)) & requested
            if stale != 0 { capturing.bitwiseAnd(~stale, ordering: .acquiringAndReleasing) }
        }
        let mask = capturing.load(ordering: .acquiring) & ~stoppedFeeds.load(ordering: .acquiring)
        noteInputGap(before: block, capturing: mask)
        var copy = 0
        while copy < rings.count {
            if mask & (1 << copy) != 0 { rings[copy].write(block) }
            copy += 1
        }
        if mask != 0 { takeFrames.add(block.frameCount, ordering: .relaxed) }
    }
}

import AudioIO
import BroadcastWave
import Foundation
@testable import Recording
import Testing

/// How a Copy joins the Take on the real-time side, and what its writer makes of the join (#85). Synchronous: each
/// test hands Capture its blocks itself.
@Suite("Copy join")
struct CopyJoinTests {
    /// Host-clock ticks run at the sample rate, so a block's host time is counted in frames.
    func capture(preRollSeconds: Double = 0) -> Capture {
        Capture(channelCount: 1, sampleRate: 48_000, preRollSeconds: preRollSeconds, hostTicksPerSecond: 48_000)
    }

    func receive(_ capture: Capture, frames: Int = 480, at hostTime: UInt64 = 0) {
        var samples = [Float](repeating: 0.25, count: frames)
        samples.withUnsafeMutableBufferPointer { buffer in
            var pointer = UnsafePointer(buffer.baseAddress!)
            withUnsafePointer(to: &pointer) {
                capture.receive(AudioBlock(channels: $0, channelCount: 1, frameCount: frames, hostTime: hostTime))
            }
        }
    }

    @Test("A Copy asked to join starts at the next block: its join frame is the Take frame before that block, and only it changes")
    func joinAtNextBlock() {
        let capture = capture()
        capture.startCapturing(copies: 1)
        receive(capture)
        capture.attachMidTake(capture.feeds[1])
        #expect(capture.feeds[1].joinedAt == nil, "nothing before the real-time thread picks it up")
        #expect(capture.feeds[1].ring.availableFrames == 0)

        receive(capture)

        #expect(capture.feeds[1].joinedAt == 480)
        #expect(capture.feeds[1].ring.availableFrames == 480)
        #expect(capture.feeds[0].ring.availableFrames == 960)
        #expect(capture.feeds[0].joinedAt == nil, "the other Copy's join frame is left alone")
        #expect(capture.takeFrameCount == 960)
    }

    @Test("A Copy no longer fed gets no more audio; the other goes on")
    func stopFeedingOne() {
        let capture = capture()
        capture.startCapturing(copies: 2)
        receive(capture)
        capture.stopFeeding(capture.feeds[0])
        receive(capture)
        #expect(capture.feeds[0].ring.availableFrames == 480)
        #expect(capture.feeds[1].ring.availableFrames == 960)
    }

    @Test("A Copy asked to join and then no longer fed, before the next block, never gets audio (#872)")
    func stopFeedingBeforeJoin() {
        let capture = capture()
        capture.startCapturing(copies: 1)
        receive(capture)
        capture.attachMidTake(capture.feeds[1])
        capture.stopFeeding(capture.feeds[1])
        receive(capture)
        #expect(capture.feeds[1].ring.availableFrames == 0)
        #expect(capture.feeds[0].ring.availableFrames == 960)
    }

    @Test("A Copy no longer fed while the real-time thread is between reading its join request and acting on it gets no audio (#544)")
    func stopFeedingDuringJoinRead() {
        let box = CaptureBox()
        let capture = Capture(channelCount: 1, sampleRate: 48_000, hostTicksPerSecond: 48_000, afterJoinRead: {
            box.capture.map { $0.stopFeeding($0.feeds[1]) }
        })
        capture.startCapturing(copies: 1)
        receive(capture)
        capture.attachMidTake(capture.feeds[1])
        box.capture = capture
        receive(capture)                                     // the Drive fails as this block reads its join request
        box.capture = nil
        receive(capture)
        #expect(capture.feeds[1].ring.availableFrames == 0)
        #expect(capture.feeds[0].ring.availableFrames == 1_440)
    }

    @Test("A Copy that lost that race and joins again is fed only from its new join block, at its new join frame (#544)")
    func rejoinAfterStopDuringJoinRead() {
        let box = CaptureBox()
        let capture = Capture(channelCount: 1, sampleRate: 48_000, hostTicksPerSecond: 48_000, afterJoinRead: {
            box.capture.map { $0.stopFeeding($0.feeds[1]) }
        })
        capture.startCapturing(copies: 1)
        receive(capture)
        capture.attachMidTake(capture.feeds[1])
        box.capture = capture
        receive(capture)
        box.capture = nil
        receive(capture)
        #expect(capture.feeds[1].ring.availableFrames == 0)

        capture.attachMidTake(capture.feeds[1])              // the Drive comes back
        receive(capture)
        #expect(capture.feeds[1].joinedAt == 1_440)
        #expect(capture.feeds[1].ring.availableFrames == 480)
    }

    @Test("A Copy no longer fed and asked to join again while a join block is acting on its old request joins at the next block (#945)")
    func stopAndRejoinDuringJoinBlock() {
        let box = CaptureBox()
        let capture = Capture(channelCount: 1, sampleRate: 48_000, hostTicksPerSecond: 48_000, afterJoinRead: {
            guard let capture = box.capture else { return }
            capture.stopFeeding(capture.feeds[1])            // the Drive fails
            capture.attachMidTake(capture.feeds[1])          // and comes straight back
        })
        capture.startCapturing(copies: 1)
        receive(capture)
        capture.attachMidTake(capture.feeds[1])
        box.capture = capture
        receive(capture)
        box.capture = nil
        #expect(capture.feeds[1].ring.availableFrames == 0, "not fed on the block that served its old request")
        receive(capture)
        #expect(capture.feeds[1].joinedAt == 960)
        #expect(capture.feeds[1].ring.availableFrames == 480)
        #expect(capture.feeds[0].ring.availableFrames == 1_440)
    }

    @Test("Stop while a join block is acting on a mid-Take Copy's request: no Copy is captured after it (#957)")
    func stopDuringJoinBlock() {
        let box = CaptureBox()
        let capture = Capture(channelCount: 1, sampleRate: 48_000, hostTicksPerSecond: 48_000, afterJoinRead: {
            box.capture?.stopCapturing()
        })
        capture.startCapturing(copies: 1)
        receive(capture)
        capture.attachMidTake(capture.feeds[1])
        box.capture = capture
        receive(capture)                                     // Stop lands as this block reads its join request
        box.capture = nil
        receive(capture)
        #expect(capture.feeds[1].ring.availableFrames == 0, "the Drive isn't added back after Stop")
        #expect(capture.feeds[0].ring.availableFrames == 480, "nor the Device, past the block before Stop")
    }

    @Test("Stop while the Pre-roll join block is acting on both Copies' requests: nothing is captured after it (#957)")
    func stopDuringPreRollJoinBlock() {
        let box = CaptureBox()
        let capture = Capture(channelCount: 1, sampleRate: 48_000, preRollSeconds: 1, hostTicksPerSecond: 48_000,
                              afterJoinRead: { box.capture?.stopCapturing() })
        receive(capture)
        capture.startCapturing(copies: 2, preRollFrames: 480)
        box.capture = capture
        receive(capture)                                     // Stop lands as this block reads the join requests
        box.capture = nil
        receive(capture)
        #expect(capture.feeds[0].ring.availableFrames == 0)
        #expect(capture.feeds[1].ring.availableFrames == 0)
    }

    /// Lets a Capture's own hook reach it.
    final class CaptureBox: @unchecked Sendable {
        var capture: Capture?
    }

    @Test("Stop before a waiting Copy has joined: no block after it is captured for any Copy (#872)")
    func stopBeforeJoin() {
        let capture = capture()
        capture.startCapturing(copies: 1)
        receive(capture)
        capture.attachMidTake(capture.feeds[1])
        capture.stopCapturing()
        receive(capture)
        #expect(capture.feeds[0].ring.availableFrames == 480)
        #expect(capture.feeds[1].ring.availableFrames == 0)
    }

    @Test("A Pre-roll Take stopped before any block: a block between the next Take's begin and its press isn't fed (#872)")
    func preRollStopBeforeAnyBlock() {
        let capture = capture(preRollSeconds: 1)
        receive(capture)
        capture.startCapturing(copies: 1, preRollFrames: 480)
        capture.stopCapturing()
        receive(capture)                                     // input returns after Stop
        #expect(capture.feeds[0].ring.availableFrames == 0, "nothing is captured after Stop")

        capture.begin(capture.feeds[0], joinedAt: nil)       // the next Take
        receive(capture)                                     // a block lands before its press
        capture.startCapturing(copies: 1, preRollFrames: 960)
        receive(capture)
        #expect(capture.feeds[0].joinedAt == 960)
        #expect(capture.feeds[0].ring.availableFrames == 480, "only the join block, no frame from before it")
    }

    @Test("With Pre-roll, both Copies join on the same block, at the Pre-roll's length, and the Pre-roll start is set there")
    func preRollJoinsBothTogether() {
        let capture = capture(preRollSeconds: 1)
        receive(capture)
        receive(capture)                                     // Ready: the Pre-roll holds 960 frames
        capture.startCapturing(copies: 2, preRollFrames: 960)
        #expect(capture.awaitingFirstBlock)
        #expect(capture.feeds.allSatisfy { $0.joinedAt == nil })

        receive(capture)

        #expect(!capture.awaitingFirstBlock)
        #expect(capture.feeds.map(\.joinedAt) == [960, 960])
        #expect(capture.preRollStart.load(ordering: .acquiring) == 960)
        #expect(capture.feeds.map(\.ring.availableFrames) == [480, 480])
        #expect(capture.takeFrameCount == 1_440)
    }

    @Test("A Copy joining on a block that comes after lost input joins before the loss, which goes into it as a drop")
    func joinAcrossInputGap() {
        let capture = capture()
        capture.startCapturing(copies: 1)
        receive(capture, at: 1)
        capture.attachMidTake(capture.feeds[1])

        receive(capture, at: 1 + 480 + 4_800)               // 4,800 frames of input lost

        #expect(capture.feeds[1].joinedAt == 480)
        #expect(capture.feeds[1].ring.nextDrop(final: true) == .init(storedFrames: 0, length: 4_800))
        #expect(capture.takeFrameCount == 480 + 4_800 + 480)
    }

    @Test("A Copy whose Pre-roll was no longer there starts with silence up to its join frame, kept as a Gap")
    func lostPreRollHeadIsAGap() throws {
        let ring = SampleRing(channelCount: 1, capacity: 1_000)
        let stem = TakeWriterDropTests.MemoryStem()
        let writer = TakeWriter(feed: CopyFeed(ring: ring, joinedAt: 480), stems: [stem], commitInterval: 48_000, head: { nil })
        TakeWriterDropTests().write(ring, from: 1, count: 100)
        writer.start()
        writer.stop()
        #expect(stem.samples == [Float](repeating: 0, count: 480) + (1...100).map(Float.init))
        #expect(writer.leadGap == 0..<480)
    }

    @Test("A Copy attached mid-Take writes silence up to the frame it joined at, then the audio from there")
    func joinHandshake() {
        let capture = capture()
        capture.startCapturing(copies: 1)
        receive(capture)
        let stem = TakeWriterDropTests.MemoryStem()
        let joinedInPause = DispatchSemaphore(value: 0)
        var pauses = 0
        // The writer is waiting for its join frame: the real-time thread's next block arrives while it pauses.
        let writer = TakeWriter(feed: capture.feeds[1], stems: [stem], commitInterval: 48_000, joinPause: {
            pauses += 1
            guard pauses == 1 else { return }
            receive(capture)
            joinedInPause.signal()
        })
        capture.attachMidTake(capture.feeds[1])
        writer.start()
        #expect(joinedInPause.wait(timeout: .now() + .seconds(120)) == .success, "the writer reached its join pause")
        writer.stop()

        #expect(pauses == 1)
        #expect(!writer.neverJoined)
        #expect(stem.samples == [Float](repeating: 0, count: 480) + [Float](repeating: 0.25, count: 480))
        #expect(writer.leadGap == 0..<480)
    }

    @Test("A Copy whose Take stops before it joins writes nothing and never joins")
    func stoppedBeforeJoin() {
        let capture = capture()
        capture.startCapturing(copies: 1)
        receive(capture)
        let stem = TakeWriterDropTests.MemoryStem()
        let writer = TakeWriter(feed: capture.feeds[1], stems: [stem], commitInterval: 48_000, joinPause: {})
        capture.attachMidTake(capture.feeds[1])
        writer.start()
        writer.stop()

        #expect(writer.neverJoined)
        #expect(capture.feeds[1].joinedAt == nil)
        #expect(stem.samples.isEmpty)
        #expect(writer.leadGap == nil)
    }

    /// A Stem that logs what the writer asks of it, in order.
    final class LoggingStem: StemSink, @unchecked Sendable {
        enum Call: Equatable {
            case append(first: Float, count: Int)
            case setMarkers
        }
        private let lock = NSLock()
        private var _calls: [Call] = []
        private var frames: UInt64 = 0
        var calls: [Call] { lock.withLock { _calls } }
        var frameCount: UInt64 { lock.withLock { frames } }
        func append(_ samples: UnsafeBufferPointer<Float>) throws {
            lock.withLock {
                _calls.append(.append(first: samples.first ?? 0, count: samples.count))
                frames += UInt64(samples.count)
            }
        }
        func commitHeader() throws {}
        func finalize() throws {}
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int {
            lock.withLock { _calls.append(.setMarkers) }
            return markers.count
        }
    }

    @Test("A Copy attached mid-Take with Markers puts them in its Stems before any of its captured audio")
    func markersBeforeFirstAudio() {
        let capture = capture()
        capture.startCapturing(copies: 1)
        receive(capture)
        let stem = LoggingStem()
        let joinedInPause = DispatchSemaphore(value: 0)
        var pauses = 0
        let writer = TakeWriter(
            feed: capture.feeds[1], stems: [stem], commitInterval: 48_000, markers: [StemMarker(position: 100, label: "Marker 1")],
            joinPause: {
                pauses += 1
                guard pauses == 1 else { return }
                receive(capture)
                joinedInPause.signal()
            })
        capture.attachMidTake(capture.feeds[1])
        writer.start()
        #expect(joinedInPause.wait(timeout: .now() + .seconds(120)) == .success, "the writer reached its join pause")
        writer.stop()

        let calls = stem.calls
        let firstMarkers = calls.firstIndex(of: .setMarkers)
        let firstAudio = calls.firstIndex(of: .append(first: 0.25, count: 480))
        #expect(firstMarkers != nil && firstAudio != nil)
        if let firstMarkers, let firstAudio { #expect(firstMarkers < firstAudio) }
        // Only the silence before the join frame comes before them.
        #expect(calls.prefix(while: { $0 != .setMarkers }) == [.append(first: 0, count: 480)])
    }
}

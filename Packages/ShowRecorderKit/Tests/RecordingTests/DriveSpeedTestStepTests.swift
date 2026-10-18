import BroadcastWave
import Foundation
@testable import Recording
import Testing

/// One step of the Drive speed test (#807): N Stems written through the real Take writer at real-time pace, and
/// whether the Drive kept up.
@Suite("Drive speed test: one step")
struct DriveSpeedTestStepTests {
    let drive = FileManager.default.temporaryDirectory.appending(path: "DriveSpeedTestStepTests-\(UUID().uuidString)")

    init() { try? FileManager.default.removeItem(at: drive) }

    struct Broken: Error {}

    /// A Stem in memory standing in for a Drive: its first `append` waits `firstAppendDelay` (a pause), every append
    /// takes `slowdown` times the audio's length (a Drive slower than real time), or every append throws.
    final class FakeStem: StemSink, @unchecked Sendable {
        private let lock = NSLock()
        private var count: UInt64 = 0
        private var delayed: Bool
        let firstAppendDelay: TimeInterval
        let slowdown: Double
        let fails: Bool
        init(firstAppendDelay: TimeInterval = 0, slowdown: Double = 0, fails: Bool = false) {
            self.firstAppendDelay = firstAppendDelay
            self.slowdown = slowdown
            self.fails = fails
            delayed = firstAppendDelay > 0
        }
        var frameCount: UInt64 { lock.withLock { count } }
        func append(_ samples: UnsafeBufferPointer<Float>) throws {
            if fails { throw Broken() }
            let wait = lock.withLock { defer { delayed = false }; return delayed }
            if wait { Thread.sleep(forTimeInterval: firstAppendDelay) }
            if slowdown > 0 { Thread.sleep(forTimeInterval: Double(samples.count) / 48_000 * slowdown) }
            lock.withLock { count += UInt64(samples.count) }
        }
        func commitHeader() throws {}
        func finalize() throws {}
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { markers.count }
    }

    /// `stem` makes the Stem for each channel number (1 first).
    private func step(
        channels: Int = 4, duration: Duration = .seconds(1), stallLimit: Duration = .seconds(1),
        isCancelled: @escaping @Sendable () -> Bool = { false }, stem: @escaping (Int) throws -> FakeStem = { _ in FakeStem() }
    ) throws -> DriveSpeedTest.StepResult {
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        return try DriveSpeedTest.runStep(
            in: drive, channels: channels, sampleRate: 48_000, duration: duration, stallLimit: stallLimit,
            isCancelled: isCancelled, makeStem: { url, _ in
                try stem(Int(url.deletingPathExtension().lastPathComponent.dropFirst(3)) ?? 0)
            })
    }

    @Test("A Drive that keeps up is reliable, and the step wrote every frame it was fed")
    func keepsUp() throws {
        let result = try step()
        #expect(result.reliable)
        #expect(result.droppedFrames == 0)
        #expect(result.worstStall < .seconds(1))
        #expect(!result.fellBehind)
        #expect(result.framesWritten >= 48_000 * 9 / 10)
        #expect(result.channels == 4)
    }

    @Test("A Drive that pauses past the stall limit is not reliable, and the worst stall is reported")
    func pauseIsAStall() throws {
        let result = try step(duration: .seconds(2), stem: { $0 == 1 ? FakeStem(firstAppendDelay: 1.6) : FakeStem() })
        #expect(!result.reliable)
        #expect(result.worstStall >= .seconds(1))
    }

    @Test("A Drive slower than real time is caught by its growing backlog, before the ring overflows")
    func slowDriveFallsBehind() throws {
        let result = try step(channels: 1, duration: .seconds(10), stem: { _ in FakeStem(slowdown: 3) })
        #expect(!result.reliable)
        #expect(result.fellBehind)
        #expect(result.droppedFrames == 0)
        #expect(result.peakBacklog >= .seconds(2))
    }

    @Test("A failed write ends the step early and is not reliable")
    func failedWrite() throws {
        let started = ContinuousClock.now
        let result = try step(duration: .seconds(30), stem: { _ in FakeStem(fails: true) })
        #expect(!result.reliable)
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test("A Stem that can't be created throws, and the scratch folder is gone")
    func stemCreationFails() throws {
        #expect(throws: Broken.self) {
            try step(stem: { channel in
                if channel == 2 { throw Broken() }
                return FakeStem()
            })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: drive.path).isEmpty)
    }

    @Test("The scratch files are gone after a step, and after a canceled one")
    func scratchRemoved() throws {
        _ = try step()
        #expect(try FileManager.default.contentsOfDirectory(atPath: drive.path).isEmpty)
        nonisolated(unsafe) var polls = 0
        let canceled = try step(duration: .seconds(30), isCancelled: { polls += 1; return polls > 20 })
        #expect(canceled.wasCanceled)
        #expect(try FileManager.default.contentsOfDirectory(atPath: drive.path).isEmpty)
    }
}

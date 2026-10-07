import BroadcastWave
import Foundation
import Synchronization

/// Drains the ring into one Stem per USB Channel on a dedicated thread, until stopped.
final class TakeWriter: @unchecked Sendable {
    private let ring: SampleRing
    private let stems: [StemWriter]
    private let running = Atomic<Bool>(true)
    private let finished = DispatchSemaphore(value: 0)
    private let failure = Mutex<(any Error)?>(nil)
    private var thread: Thread?
    /// Frames between header commits, so a crash loses at most this much (#6).
    private let commitInterval: Int
    private var framesSinceCommit = 0
    /// Markers waiting to be written into the Stems by the writer thread.
    private let pendingMarkers = Mutex<[StemMarker]?>(nil)

    init(ring: SampleRing, stems: [StemWriter], commitInterval: Int) {
        self.ring = ring
        self.stems = stems
        self.commitInterval = commitInterval
    }

    /// Replaces the Stems' Markers. Applied on the writer thread before its next write, and on disk
    /// from the next header commit.
    func setMarkers(_ markers: [StemMarker]) {
        pendingMarkers.withLock { $0 = markers }
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "ShowRecorder Take writer"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    /// Drains whatever is left, finalizes every Stem and waits for the thread to finish.
    func stop() throws {
        running.store(false, ordering: .releasing)
        finished.wait()
        if let error = failure.withLock({ $0 }) { throw error }
    }

    private func run() {
        do {
            // Commit once up front so even a Take that dies early leaves files that open.
            for stem in stems { try stem.commitHeader() }
            while true {
                let stillRunning = running.load(ordering: .acquiring)
                if let markers = pendingMarkers.withLock({ pending in defer { pending = nil }; return pending }) {
                    for stem in stems { try stem.setMarkers(markers) }
                }
                let drained = try drainOnce()
                framesSinceCommit += drained
                if framesSinceCommit >= commitInterval {
                    for stem in stems { try stem.commitHeader() }
                    framesSinceCommit = 0
                }
                if drained == 0 {
                    if !stillRunning { break }
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
            for stem in stems { try stem.finalize() }
        } catch {
            failure.withLock { $0 = error }
        }
        finished.signal()
    }

    private func drainOnce() throws -> Int {
        try ring.consume(maxFrames: 4096) { channel, samples in
            try stems[channel].append(samples)
        }
    }
}

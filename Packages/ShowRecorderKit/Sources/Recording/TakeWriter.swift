import BroadcastWave
import Foundation
import Synchronization

/// Drains the ring into one Stem per USB Channel on a dedicated thread, until stopped.
final class TakeWriter: @unchecked Sendable {
    private let ring: SampleRing
    private let stems: [any StemSink]
    private let running = Atomic<Bool>(true)
    private let finished = DispatchSemaphore(value: 0)
    private let failed = Atomic<Bool>(false)
    /// Called on the writer thread when this Copy fails, so capture can stop feeding it.
    private let onFailure: @Sendable () -> Void
    private var thread: Thread?
    /// Frames between header commits, so a crash loses at most this much (#6).
    private let commitInterval: Int
    private var framesSinceCommit = 0
    /// Markers waiting to be written into the Stems by the writer thread.
    private let pendingMarkers = Mutex<[StemMarker]?>(nil)

    init(ring: SampleRing, stems: [any StemSink], commitInterval: Int, onFailure: @escaping @Sendable () -> Void = {}) {
        self.onFailure = onFailure
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

    /// Whether a write failed. The Copy stops there; the Take carries on in the other Copies.
    var hasFailed: Bool { failed.load(ordering: .acquiring) }

    /// Drains whatever is left, finalizes every Stem and waits for the thread to finish.
    /// A failed Copy doesn't throw: it's reported through `hasFailed`.
    func stop() {
        running.store(false, ordering: .releasing)
        finished.wait()
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
            failed.store(true, ordering: .releasing)
            onFailure()
            ring.discardAll()
            // Close what can be closed, so the Stems that did get written open.
            for stem in stems { try? stem.finalize() }
        }
        finished.signal()
    }

    private func drainOnce() throws -> Int {
        try ring.consume(maxFrames: 4096) { channel, samples in
            try stems[channel].append(samples)
        }
    }
}

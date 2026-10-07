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

    init(ring: SampleRing, stems: [StemWriter]) {
        self.ring = ring
        self.stems = stems
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
            while true {
                let stillRunning = running.load(ordering: .acquiring)
                let drained = try drainOnce()
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

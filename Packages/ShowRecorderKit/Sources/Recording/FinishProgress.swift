import Synchronization

/// How much audio a Stop still has to write to the Drive (#817): set by the finish thread, read by the screen about once a
/// second. Atomics, so neither side waits on the other.
public final class FinishProgress: Sendable {
    private let driveBacklogMilliseconds = Atomic<Int>(0)

    private let savingToDrive = Atomic<Bool>(false)

    init() {}

    /// Whether the Drive is still being written: from Stop until the Take is published, including finalizing the Stems and
    /// writing Take.json, not only while audio waits. Off for a Drive Stop gave up on. The screen says "don't unplug" while it's on.
    public var isSavingToDrive: Bool { savingToDrive.load(ordering: .relaxed) }

    func setSavingToDrive(_ saving: Bool) { savingToDrive.store(saving, ordering: .relaxed) }

    /// Seconds of audio waiting to be written to the Drive Copy; 0 when there is none, or no Drive Copy.
    public var driveBacklogSeconds: Double { Double(driveBacklogMilliseconds.load(ordering: .relaxed)) / 1000 }

    func setDriveBacklog(frames: Int, sampleRate: Int) {
        let milliseconds = sampleRate > 0 ? frames * 1000 / sampleRate : 0
        driveBacklogMilliseconds.store(max(0, milliseconds), ordering: .relaxed)
    }
}

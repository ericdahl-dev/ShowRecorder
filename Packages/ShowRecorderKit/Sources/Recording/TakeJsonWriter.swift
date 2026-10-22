import Foundation
import Synchronization
import TakeFile

/// Writes `Take.json` into one Take folder on a thread of its own (#914), so a slow stick can't hold up the main thread.
/// Writes don't queue up: while one is under way only the newest state waits, and each lands in order, so an older state
/// never replaces a newer one. The file is staged beside `Take.json` and moved into place only while the writer is open,
/// so once `close()` returns nothing a write still stuck on the stick finishes can replace what came after. The state lock
/// is never held across file work, so `submit` (the main thread) and `close` never wait on the stick; `close` waits a moment
/// for a move into place under way, and gives up on one that hangs.
final class TakeJsonWriter: Sendable {
    private struct State {
        var pending: TakeMetadata?
        var isScheduled = false
        var isClosed = false
    }

    private let folder: URL
    private let stage: @Sendable (Data, URL) throws -> Void
    private let move: @Sendable (URL, URL) -> Bool
    private let queue = DispatchQueue(label: "ShowRecorder Take.json writer", qos: .utility)
    private let state = Mutex(State())
    /// Held while a staged file is moved into place, so `close` can tell none is under way.
    private let moving = NSLock()

    /// `stage` writes the data to the file it's given; a Take's own `Take.json` is replaced only once that is done.
    /// `move` puts the staged file over `Take.json` in one step; tests hold it.
    init(folder: URL, stage: @escaping @Sendable (Data, URL) throws -> Void,
         move: @escaping @Sendable (URL, URL) -> Bool = { rename($0.path, $1.path) == 0 }) {
        self.folder = folder
        self.stage = stage
        self.move = move
    }

    /// Queues `metadata` as the newest state to write. Returns at once.
    func submit(_ metadata: TakeMetadata) {
        let start = state.withLock { state -> Bool in
            guard !state.isClosed else { return false }
            state.pending = metadata
            guard !state.isScheduled else { return false }
            state.isScheduled = true
            return true
        }
        if start { queue.async { self.drain() } }
    }

    /// Stops writing: what is queued is dropped, and a write under way is not moved into place when it finishes. The
    /// caller writes the final `Take.json` itself afterwards. A move into place already under way is waited for, up to
    /// `moveWait`: a stick that hangs inside it is the Copy Stop gives up on.
    func close(moveWait: TimeInterval = 1) {
        state.withLock { state in
            state.isClosed = true
            state.pending = nil
        }
        if moving.lock(before: Date(timeIntervalSinceNow: moveWait)) { moving.unlock() }
    }

    private func drain() {
        while let metadata = state.withLock({ state -> TakeMetadata? in
            defer { state.pending = nil }
            guard !state.isClosed, let next = state.pending else { state.isScheduled = false; return nil }
            return next
        }) {
            write(metadata)
        }
    }

    private func write(_ metadata: TakeMetadata) {
        guard let data = try? metadata.encoded() else { return }
        let target = folder.appending(path: TakeMetadata.fileName)
        let staged = folder.appending(path: ".\(TakeMetadata.fileName).\(UUID().uuidString)")
        guard (try? stage(data, staged)) != nil else {
            try? FileManager.default.removeItem(at: staged)
            return
        }
        // Moved into place while `moving` is held, which `close()` waits on after it closes: the move lands before the
        // caller's final write or not at all.
        moving.lock()
        defer { moving.unlock() }
        // rename(2) replaces the file in one step, so a reader never finds Take.json missing.
        if state.withLock({ $0.isClosed }) || !move(staged, target) {
            try? FileManager.default.removeItem(at: staged)
        }
    }
}

/// The Take's `Take.json` writers, one per Copy folder: a Drive that hangs can't hold up the Device's.
final class TakeJsonWriters: Sendable {
    private let writers = Mutex<[URL: TakeJsonWriter]>([:])
    private let stage = Mutex<@Sendable (Data, URL) throws -> Void>({ try $0.write(to: $1) })

    /// How a write is staged: the data into the file it's given. Tests slow it down.
    func setStage(_ stage: @escaping @Sendable (Data, URL) throws -> Void) {
        self.stage.withLock { $0 = stage }
    }

    func submit(_ metadata: TakeMetadata, to folders: [URL]) {
        let stage = stage.withLock { $0 }
        for folder in folders {
            writers.withLock { writers in
                if let writer = writers[folder] { return writer }
                let writer = TakeJsonWriter(folder: folder, stage: stage)
                writers[folder] = writer
                return writer
            }.submit(metadata)
        }
    }

    /// Closes every writer: none writes again, and none finishes a write already under way into place.
    func close() {
        for writer in writers.withLock({ Array($0.values) }) { writer.close() }
    }
}

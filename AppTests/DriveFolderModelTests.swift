import Destinations
import Foundation
import Testing
@testable import ShowRecorder

/// The record screen re-reads the Drive every few seconds so an unplugged one shows before record is pressed. That read
/// resolves the bookmark and asks the volume, which a USB stick busy with a Take answers slowly (#814): it doesn't ask
/// the Drive during a Take, and between Takes it doesn't run on the main actor.
@MainActor
struct DriveFolderModelTests {
    /// Counts reads and notes which thread made them. With `holdsFirst`, the first read waits until `release()`; it
    /// finds no Drive, and every later read finds one that is gone, so the two results differ.
    final class TestStorage: BookmarkStorage, @unchecked Sendable {
        private let condition = NSCondition()
        private var loads = 0
        private var mainLoads = 0
        private var firstBegan = false
        private var released = false
        let holdsFirst: Bool

        init(holdsFirst: Bool = false) { self.holdsFirst = holdsFirst }

        var loadCount: Int { condition.withLock { loads } }
        var loadsOnMain: Int { condition.withLock { mainLoads } }
        var hasBeganFirst: Bool { condition.withLock { firstBegan } }

        func release() {
            condition.lock()
            released = true
            condition.broadcast()
            condition.unlock()
        }

        func load() -> StoredDriveFolder? {
            condition.lock()
            loads += 1
            let number = loads
            if Thread.isMainThread { mainLoads += 1 }
            if number == 1 {
                firstBegan = true
                while holdsFirst, !released { condition.wait() }
            }
            condition.unlock()
            return number == 1 && holdsFirst ? nil : (holdsFirst ? StoredDriveFolder(bookmark: Data("gone".utf8), name: "T7") : nil)
        }

        func save(_ folder: StoredDriveFolder?) {}
    }

    /// Yields the main actor until the first read has begun; the minute only guards against a hang.
    func awaitFirstRead(_ storage: TestStorage) async {
        let deadline = ContinuousClock.now + .seconds(60)
        while !storage.hasBeganFirst, ContinuousClock.now < deadline { await Task.yield() }
    }

    @Test("While a Take is busy the periodic refresh doesn't ask the Drive, but the Device's free space stays current")
    func nothingDuringATake() async {
        let storage = TestStorage()
        let model = DriveFolderModel(store: DriveFolderStore(storage: storage))

        await model.refreshInBackground(whileBusy: true)

        #expect(storage.loadCount == 0)
        #expect(model.deviceAvailableBytes > 0)
    }

    @Test("Between Takes the refresh reads the Drive off the main thread and publishes what it found")
    func readsOffMain() async {
        let storage = TestStorage()
        let model = DriveFolderModel(store: DriveFolderStore(storage: storage))

        await model.refreshInBackground(whileBusy: false)

        #expect(storage.loadCount == 1)
        #expect(storage.loadsOnMain == 0)
        #expect(model.status == .notChosen)
    }

    @Test("A refresh that comes while one is still reading returns at once and reads nothing more")
    func oneAtATime() async {
        let storage = TestStorage(holdsFirst: true)
        let model = DriveFolderModel(store: DriveFolderStore(storage: storage))

        let first = Task { await model.refreshInBackground(whileBusy: false) }
        await awaitFirstRead(storage)
        await model.refreshInBackground(whileBusy: false)   // returns with the first still held on the gate

        #expect(storage.loadCount == 1)
        storage.release()
        await first.value
        #expect(storage.loadCount == 1)
    }

    @Test("A read that finishes after a newer one doesn't overwrite it")
    func staleReadIsDropped() async {
        let storage = TestStorage(holdsFirst: true)
        let model = DriveFolderModel(store: DriveFolderStore(storage: storage))
        let first = Task { await model.refreshInBackground(whileBusy: false) }
        await awaitFirstRead(storage)

        model.refresh()   // Check Drive, a chosen folder: a newer read, and the Drive is gone
        let newer = model.status
        storage.release()
        await first.value

        #expect(newer != .notChosen, "the newer read found the saved Drive gone")
        #expect(model.status == newer, "and the older one, which found no Drive, didn't overwrite it")
    }

    @Test("A read that finishes after a Take began doesn't publish")
    func readDuringATakeIsDropped() async {
        let storage = TestStorage(holdsFirst: true)
        let model = DriveFolderModel(store: DriveFolderStore(storage: storage))
        var busy = false
        let first = Task { await model.refreshInBackground(whileBusy: false, stillIdle: { !busy }) }
        await awaitFirstRead(storage)

        busy = true   // the press came while the stick was answering
        storage.release()
        await first.value

        #expect(model.status == .notChosen, "nothing was published")
    }
}

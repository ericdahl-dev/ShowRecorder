import Destinations
import Foundation
import Testing

@Suite("Drive folder")
struct DriveFolderStoreTests {
    let folder: URL
    let storage: InMemoryBookmarkStorage

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "DriveFolderStoreTests-\(UUID().uuidString)/Gig Drive")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storage = InMemoryBookmarkStorage()
    }

    @Test("A chosen folder is remembered across launches")
    func chosenFolderIsRemembered() throws {
        try DriveFolderStore(storage: storage).choose(folder)

        let status = DriveFolderStore(storage: storage).status()   // a new store, as after relaunch

        guard case .available(let drive) = status else {
            Issue.record("expected available, got \(status)")
            return
        }
        #expect(drive.folder.standardizedFileURL.path == folder.standardizedFileURL.path)
        #expect(drive.name == "Gig Drive")
        #expect(drive.availableBytes > 0)
    }

    @Test("A Drive remembered under its mount point's UUID (as 1.1.x saved an iPhone's SSD) shows the name the system gives it")
    func uuidNameIsReplaced() throws {
        try DriveFolderStore(storage: storage).choose(folder)
        let saved = try #require(storage.load())
        storage.save(StoredDriveFolder(bookmark: saved.bookmark, name: "7651E04F-85E1-4466-9F7F-F59B8ED0EA24"))

        guard case .available(let drive) = DriveFolderStore(storage: storage).status() else {
            Issue.record("expected available")
            return
        }
        #expect(drive.name == "Gig Drive")
        #expect(storage.load()?.name == "Gig Drive", "kept, for when the Drive is unplugged")
    }

    @Test("When the system can't say the Drive's name (still mounting, say), the remembered name stays: never the UUID")
    func nameLookupFails() throws {
        try DriveFolderStore(storage: storage).choose(folder)
        let saved = try #require(storage.load())
        storage.save(StoredDriveFolder(bookmark: saved.bookmark, name: "ShowRecorder"))

        let status = DriveFolderStore(storage: storage, shownName: { _ in nil }).status()

        guard case .available(let drive) = status else {
            Issue.record("expected available")
            return
        }
        #expect(drive.name == "ShowRecorder")
        #expect(storage.load()?.name == "ShowRecorder")
    }

    @Test("With no Drive chosen there is no problem to report (#814)")
    func noProblemWhenNotChosen() {
        #expect(DriveFolderStore(storage: storage).problemDescription() == nil)
    }

    @Test("A Drive that is there now says so: it wasn't ready when the press asked (#814)")
    func problemWhenAvailableNow() throws {
        try DriveFolderStore(storage: storage).choose(folder)

        let problem = try #require(DriveFolderStore(storage: storage).problemDescription())

        #expect(problem.contains("available now"))
    }

    @Test("A saved link that can't be opened is told apart from a missing folder (#814)")
    func problemWhenLinkIsBroken() throws {
        storage.save(StoredDriveFolder(bookmark: Data("not a bookmark".utf8), name: "T7 Shield"))

        let problem = try #require(DriveFolderStore(storage: storage).problemDescription())

        #expect(problem.contains("saved link"))
        #expect(problem.contains("T7 Shield"))
    }

    @Test("A folder that went away says which Drive and that it isn't there (#814)")
    func problemWhenFolderIsGone() throws {
        try DriveFolderStore(storage: storage).choose(folder)
        try FileManager.default.removeItem(at: folder)

        let problem = try #require(DriveFolderStore(storage: storage).problemDescription())

        // Which step fails first (the saved link or the folder) depends on the system; either way it names the Drive.
        #expect(problem.contains("Gig Drive"))
        #expect(problem.contains("couldn't be opened") || problem.contains("isn't there"))
    }

    @Test("Asking the status again and again doesn't write anything while the name is unchanged")
    func noWritesWhenUnchanged() throws {
        let counting = CountingStorage()
        try DriveFolderStore(storage: counting).choose(folder)
        let saves = counting.saves

        for _ in 0..<5 { _ = DriveFolderStore(storage: counting).status() }

        #expect(counting.saves == saves)
    }

    @Test("Before a folder is chosen, the status says so")
    func notChosenByDefault() {
        #expect(DriveFolderStore(storage: storage).status() == .notChosen)
    }

    @Test("When the Drive folder is gone, it's reported as not connected")
    func goneFolderIsNotConnected() throws {
        let store = DriveFolderStore(storage: storage)
        try store.choose(folder)
        try FileManager.default.removeItem(at: folder)

        #expect(store.status() == .unavailable(.notConnected(name: "Gig Drive")))
    }

    @Test("A read-only folder is refused when it's chosen, and nothing is remembered")
    func readOnlyFolderRefused() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let store = DriveFolderStore(storage: storage)

        #expect(throws: DriveProblem.notWritable(name: "Gig Drive")) { try store.choose(folder) }
        #expect(store.status() == .notChosen)
    }

    @Test("A bookmark that no longer resolves is reported as not connected")
    func unresolvableBookmarkIsNotConnected() {
        storage.save(StoredDriveFolder(bookmark: Data([0, 1, 2, 3]), name: "Old Drive"))

        #expect(DriveFolderStore(storage: storage).status() == .unavailable(.notConnected(name: "Old Drive")))
    }

    @Test("Choosing a folder leaves no probe file behind")
    func choosingLeavesNoProbeFile() throws {
        try DriveFolderStore(storage: storage).choose(folder)

        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test("Forgetting the Drive folder returns to not chosen")
    func forgetReturnsToNotChosen() throws {
        let store = DriveFolderStore(storage: storage)
        try store.choose(folder)

        store.forget()

        #expect(store.status() == .notChosen)
    }

    @Test("Access for a Take gives the Drive folder while it's available, and nothing otherwise")
    func beginAccessOnlyWhenAvailable() throws {
        let store = DriveFolderStore(storage: storage)
        #expect(store.beginAccess() == nil)

        try store.choose(folder)
        let access = try #require(store.beginAccess())
        #expect(access.folder.standardizedFileURL.path == folder.standardizedFileURL.path)
        access.end()

        try FileManager.default.removeItem(at: folder)
        #expect(store.beginAccess() == nil)
    }

    @Test("Free space for a folder not made yet is read where it will be, not reported as none")
    func freeSpaceForFolderNotMadeYet() {
        let shows = folder.appending(path: "Shows", directoryHint: .isDirectory)
        #expect(DriveFolderStore.availableBytes(at: shows) == 0, "a missing folder has no volume to ask")

        #expect(DriveFolderStore.availableBytes(forFolder: shows) > 0)
        #expect(DriveFolderStore.availableBytes(forFolder: folder) > 0)
    }
}

/// Remembers the Drive folder in memory and counts the saves.
final class CountingStorage: BookmarkStorage, @unchecked Sendable {
    private let inner = InMemoryBookmarkStorage()
    private(set) var saves = 0

    func load() -> StoredDriveFolder? { inner.load() }
    func save(_ folder: StoredDriveFolder?) {
        saves += 1
        inner.save(folder)
    }
}

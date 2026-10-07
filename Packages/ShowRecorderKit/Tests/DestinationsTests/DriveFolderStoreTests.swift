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
}

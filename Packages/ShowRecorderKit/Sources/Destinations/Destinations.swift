import Foundation
import Synchronization

/// The two places a Take is written, and the one identity of a Copy: the Device's and the Drive's.
/// The raw values are what `Take.json` stores.
public enum DestinationKind: String, Codable, Sendable, Hashable, CaseIterable {
    case device, drive

    /// The Copy's position wherever Copies are kept in order: the Device first.
    public var index: Int {
        switch self {
        case .device: 0
        case .drive: 1
        }
    }

    /// "Device" or "Drive", as the operator reads it.
    public var name: String {
        switch self {
        case .device: "Device"
        case .drive: "Drive"
        }
    }
}

/// Where the Drive folder's bookmark is kept between launches. One per device.
public protocol BookmarkStorage: Sendable {
    func load() -> StoredDriveFolder?
    func save(_ folder: StoredDriveFolder?)
}

/// A remembered Drive folder: its bookmark and the name shown when it can't be found.
public struct StoredDriveFolder: Codable, Equatable, Sendable {
    public var bookmark: Data
    public var name: String

    public init(bookmark: Data, name: String) {
        self.bookmark = bookmark
        self.name = name
    }
}

/// Keeps the Drive folder in `UserDefaults`, which is thread-safe but not marked `Sendable`.
public final class UserDefaultsBookmarkStorage: BookmarkStorage, @unchecked Sendable {
    private let key: String
    private let defaults: UserDefaults

    public init(key: String = "driveFolder", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func load() -> StoredDriveFolder? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(StoredDriveFolder.self, from: $0) }
    }

    public func save(_ folder: StoredDriveFolder?) {
        if let folder, let data = try? JSONEncoder().encode(folder) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Keeps the Drive folder in memory, for tests and previews.
public final class InMemoryBookmarkStorage: BookmarkStorage {
    private let folder = Mutex<StoredDriveFolder?>(nil)

    public init() {}

    public func load() -> StoredDriveFolder? { folder.withLock { $0 } }
    public func save(_ folder: StoredDriveFolder?) { self.folder.withLock { $0 = folder } }
}

/// A Drive folder that's connected and writable right now.
public struct Drive: Equatable, Sendable {
    public var folder: URL
    /// The folder's name, as the operator chose it.
    public var name: String
    /// Free space on the Drive's volume.
    public var availableBytes: Int64

    public init(folder: URL, name: String, availableBytes: Int64) {
        self.folder = folder
        self.name = name
        self.availableBytes = availableBytes
    }
}

public enum DriveProblem: Error, Equatable, Sendable {
    /// The Drive isn't connected, or the folder was moved or deleted.
    case notConnected(name: String)
    /// The folder can't be written to.
    case notWritable(name: String)

    public var message: String {
        switch self {
        case .notConnected(let name):
            "The Drive folder \"\(name)\" isn't available. Connect the Drive, or choose the folder again."
        case .notWritable(let name):
            "ShowRecorder can't write to \"\(name)\". Choose a folder on a Drive that isn't read-only."
        }
    }
}

public enum DriveStatus: Equatable, Sendable {
    case notChosen
    case available(Drive)
    case unavailable(DriveProblem)
}

/// The operator's Drive folder: chosen once, remembered with a security-scoped bookmark.
public struct DriveFolderStore: Sendable {
    private let storage: any BookmarkStorage
    /// The folder's name as the system shows it, nil when it can't say (`shownName(of:)`).
    private let shownName: @Sendable (URL) -> String?

    public init(storage: any BookmarkStorage = UserDefaultsBookmarkStorage(), shownName: @escaping @Sendable (URL) -> String? = Self.shownName(of:)) {
        self.storage = storage
        self.shownName = shownName
    }

    /// Remembers `folder` (from the system folder picker) after checking it can be written to.
    public func choose(_ folder: URL) throws(DriveProblem) {
        let name = Self.withAccess(to: folder) { shownName($0) } ?? folder.lastPathComponent
        let bookmark: Data
        do {
            bookmark = try Self.withAccess(to: folder) { url in
                try Self.verifyWritable(url)
                return try url.bookmarkData(options: Self.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            }
        } catch {
            throw .notWritable(name: name)
        }
        storage.save(StoredDriveFolder(bookmark: bookmark, name: name))
    }

    /// Forgets the Drive folder.
    public func forget() {
        storage.save(nil)
    }

    /// Why the Drive wasn't found, step by step, for the record of a Take that started without it (#814): the saved link
    /// that can't be opened, the folder that isn't there, or "available now" when it was only slow to mount. Nil with no
    /// Drive chosen. `status()` calls all of these `notConnected`, which hides which step failed.
    public func problemDescription() -> String? {
        guard let stored = storage.load() else { return nil }
        var isStale = false
        let folder: URL
        do {
            folder = try URL(resolvingBookmarkData: stored.bookmark, options: Self.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            let ns = error as NSError
            return "The saved link to \"\(stored.name)\" couldn't be opened (\(ns.domain) \(ns.code))."
        }
        return Self.withAccess(to: folder) { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return "The folder on \"\(stored.name)\" isn't there."
            }
            return "\"\(stored.name)\" is available now, so it was not ready when the press asked."
        }
    }

    /// Runs `work` on a thread of its own and returns its result, for a caller on the main actor (#814): resolving the
    /// bookmark, asking a volume for its name or free space and the like can take hundreds of milliseconds on a USB stick
    /// busy with a Take. A thread, not a task, because a task that blocks holds a cooperative pool thread.
    public static func onOwnThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: work()) }
            thread.name = "ShowRecorder Drive"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    /// `status()` on a thread of its own (see `onOwnThread`).
    public func currentStatus() async -> DriveStatus {
        let store = self
        return await Self.onOwnThread { store.status() }
    }

    /// Whether the remembered Drive folder is connected and writable right now.
    public func status() -> DriveStatus {
        guard let stored = storage.load() else { return .notChosen }
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: stored.bookmark, options: Self.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return .unavailable(.notConnected(name: stored.name))
        }
        return Self.withAccess(to: folder) { url -> DriveStatus in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return .unavailable(.notConnected(name: stored.name))
            }
            // Only a name the system gave is saved: when it can't say (the Drive still mounting), the path's last
            // component on an iPhone is a UUID, and the name remembered for when it's unplugged is better.
            let shown = shownName(url)
            let name = shown ?? stored.name
            if isStale, let fresh = try? url.bookmarkData(options: Self.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
                storage.save(StoredDriveFolder(bookmark: fresh, name: name))
            } else if shown != nil, name != stored.name {
                storage.save(StoredDriveFolder(bookmark: stored.bookmark, name: name))
            }
            return .available(Drive(folder: url, name: name, availableBytes: Self.availableBytes(at: url)))
        }
    }

    /// Opens the Drive folder for a Take: resolves the bookmark and keeps its security scope until
    /// `end()` is called. Nil when the Drive folder isn't chosen, connected or writable.
    public func beginAccess() -> DriveAccess? {
        guard case .available(let drive) = status() else { return nil }
        let folder = drive.folder
        guard folder.startAccessingSecurityScopedResource() else {
            return DriveAccess(folder: folder, stop: {})  // no scope to hold outside a sandbox
        }
        return DriveAccess(folder: folder, stop: { folder.stopAccessingSecurityScopedResource() })
    }

    // MARK: - Helpers

    /// The folder's name as the system shows it; nil when it can't say. An iPhone's or iPad's SSD is mounted at a UUID
    /// ("7651E04F-…"), so the path's last component isn't its name; the localized name is the volume's ("T7 Shield")
    /// at its root, and the folder's own name inside it.
    public static func shownName(of folder: URL) -> String? {
        let shown = try? folder.resourceValues(forKeys: [.localizedNameKey]).localizedName
        return shown.flatMap { $0.isEmpty ? nil : $0 }
    }

    #if os(macOS)
    private static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
    #else
    private static let creationOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withoutUI]
    #endif

    /// Runs `body` inside the folder's security scope. Outside a sandbox there's no scope to start,
    /// which is fine.
    static func withAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    /// Writes and removes a small file, so a read-only Drive is caught when it's chosen.
    static func verifyWritable(_ folder: URL) throws {
        let probe = folder.appending(path: ".ShowRecorder-write-check-\(UUID().uuidString)")
        try Data("ShowRecorder".utf8).write(to: probe, options: .atomic)
        try FileManager.default.removeItem(at: probe)
    }

    /// Free space on the volume holding `url` (for example the Device's Documents folder).
    public static func availableBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return Int64(values?.volumeAvailableCapacity ?? 0)
    }

    /// Free space where `folder` is, or will be once it's made: until then, read at its nearest existing parent.
    /// For the Device's Documents/Shows, which the first Show creates.
    public static func availableBytes(forFolder folder: URL) -> Int64 {
        var url = folder
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
        }
        return availableBytes(at: url)
    }
}

/// The Drive folder opened for one Take, held until the Take is finalized and Repaired. `end()` lets it go
/// (for a bookmarked folder, its security scope).
public struct DriveAccess: Sendable {
    public let folder: URL
    private let stop: @Sendable () -> Void

    public init(folder: URL, stop: @escaping @Sendable () -> Void = {}) {
        self.folder = folder
        self.stop = stop
    }

    public func end() { stop() }
}

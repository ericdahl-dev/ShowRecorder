import Foundation
import Synchronization

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

    public init(storage: any BookmarkStorage = UserDefaultsBookmarkStorage()) {
        self.storage = storage
    }

    /// Remembers `folder` (from the system folder picker) after checking it can be written to.
    public func choose(_ folder: URL) throws(DriveProblem) {
        let name = folder.lastPathComponent
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
            if isStale, let fresh = try? url.bookmarkData(options: Self.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
                storage.save(StoredDriveFolder(bookmark: fresh, name: stored.name))
            }
            return .available(Drive(folder: url, name: stored.name, availableBytes: Self.availableBytes(at: url)))
        }
    }

    // MARK: - Helpers

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

    static func availableBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return Int64(values?.volumeAvailableCapacity ?? 0)
    }
}

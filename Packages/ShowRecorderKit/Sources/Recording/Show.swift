import Foundation

/// One event being recorded. Holds one or more Takes, each in its own folder, with a Copy on the
/// Device and, when a Drive folder is available, a Copy on the Drive under the same name.
public struct Show: Sendable, Equatable {
    public let name: String
    /// The Show folder on the Device.
    public let folder: URL
    /// The Show folder on the Drive, when the current Take is also written there.
    public private(set) var driveFolder: URL?
    public private(set) var takeCount: Int
    /// When the Show started. Written to `Show.json` in every Copy.
    public let startedAt: Date
    /// When the Show was ended, or nil while it is open.
    public private(set) var endedAt: Date?
    /// Where the Show is, as the operator typed it. Nil when none was given.
    public let venue: String?

    init(name: String, folder: URL, driveFolder: URL? = nil, takeCount: Int, startedAt: Date = .distantPast, endedAt: Date? = nil, venue: String? = nil) {
        self.venue = venue
        self.name = name
        self.folder = folder
        self.driveFolder = driveFolder
        self.takeCount = takeCount
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    /// Every Copy of the Show folder, the Device first.
    public var copies: [Show] {
        [Show(name: name, folder: folder, takeCount: takeCount, startedAt: startedAt, endedAt: endedAt)]
            + (driveFolder.map { [Show(name: name, folder: $0, takeCount: takeCount, startedAt: startedAt, endedAt: endedAt)] } ?? [])
    }

    /// Creates the Show folder on the Device (and on the Drive, if given), named "YYYY-MM-DD Show"
    /// from the start date. If that name is taken on either, a number is added ("… Show 2").
    static func create(in deviceParent: URL, drive driveParent: URL?, on date: Date, name given: String? = nil, venue: String? = nil) throws -> Show {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let trimmed = Self.folderSafe(given ?? "")
        let base = String(format: "%04d-%02d-%02d ", c.year ?? 0, c.month ?? 0, c.day ?? 0) + (trimmed.isEmpty ? "Show" : trimmed)
        let fm = FileManager.default
        let parents = [deviceParent] + (driveParent.map { [$0] } ?? [])
        for parent in parents { try fm.createDirectory(at: parent, withIntermediateDirectories: true) }
        var name = base
        var suffix = 2
        while parents.contains(where: { fm.fileExists(atPath: $0.appending(path: name).path) }) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        let folder = deviceParent.appending(path: name, directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let venue = venue?.trimmingCharacters(in: .whitespacesAndNewlines)
        var show = Show(name: name, folder: folder, takeCount: 0, startedAt: date, venue: venue?.isEmpty == false ? venue : nil)
        try show.file.write(to: folder)
        try show.useDrive(driveParent)
        return show
    }

    /// A name the operator typed, made usable as a folder name: trimmed, "/" and ":" turned into "-", and
    /// leading dots dropped so the folder isn't hidden. It is never refused.
    static func folderSafe(_ name: String) -> String {
        var safe = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        while safe.hasPrefix(".") { safe.removeFirst() }
        return safe.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Writes this Show's next Takes to the Drive folder `parent` as well (creating the Show folder
    /// there under the same name), or to the Device only when `parent` is nil.
    mutating func useDrive(_ parent: URL?) throws {
        guard let parent else {
            driveFolder = nil
            return
        }
        let folder = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        driveFolder = folder
        try file.write(to: folder)
    }

    /// What `Show.json` holds for this Show.
    var file: ShowFile { ShowFile(name: name, startedAt: startedAt, endedAt: endedAt, venue: venue) }

    /// Marks the Show ended in every Copy it has. A Copy that can't be written is skipped: the Show ends anyway.
    mutating func end(at date: Date) {
        endedAt = date
        for copy in [folder] + (driveFolder.map { [$0] } ?? []) { try? file.write(to: copy) }
    }

    /// The Show that was left open: the one in `deviceParent` with a readable `Show.json` that isn't ended,
    /// newest start first. Any other open Show is marked ended (one Show is open at a time). Folders without
    /// a readable `Show.json`, such as Shows from before it existed, are left alone and never picked.
    static func findOpen(in deviceParent: URL) -> Show? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: deviceParent.path) else { return nil }
        var open: [(folder: URL, file: ShowFile)] = []
        for name in names {
            let folder = deviceParent.appending(path: name, directoryHint: .isDirectory)
            guard let file = ShowFile.read(from: folder), file.endedAt == nil else { continue }
            open.append((folder, file))
        }
        open.sort { $0.file.startedAt > $1.file.startedAt }
        guard let newest = open.first else { return nil }
        for older in open.dropFirst() {
            var ended = older.file
            ended.endedAt = newest.file.startedAt
            try? ended.write(to: older.folder)
        }
        let takes = ((try? fm.contentsOfDirectory(atPath: newest.folder.path)) ?? [])
            .compactMap { $0.hasPrefix("Take ") ? Int($0.dropFirst(5)) : nil }
        return Show(name: newest.file.name, folder: newest.folder, takeCount: takes.max() ?? 0, startedAt: newest.file.startedAt)
    }

    /// Starts writing the running Take to the Drive folder `parent` too: the Show folder there (under
    /// the same name) and a folder for the current Take. Returns that Take folder.
    mutating func joinDrive(_ parent: URL) throws -> URL {
        try useDrive(parent)
        let takeFolder = driveFolder!.appending(path: String(format: "Take %02d", takeCount), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: takeFolder, withIntermediateDirectories: false)
        return takeFolder
    }

    /// Creates "Take NN" for the next Take in every Copy and returns the folders, the Device first.
    mutating func createNextTakeFolder() throws -> [URL] {
        takeCount += 1
        let takeName = String(format: "Take %02d", takeCount)
        return try ([folder] + (driveFolder.map { [$0] } ?? [])).map { showFolder in
            let takeFolder = showFolder.appending(path: takeName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: takeFolder, withIntermediateDirectories: false)
            return takeFolder
        }
    }
}

/// A Show's `Show.json`: its name as in the folder, when it started and, once it is over, when it ended.
/// Written when the Show is created, in every Copy, so the open Show survives a crash or relaunch.
struct ShowFile: Codable, Equatable {
    static let fileName = "Show.json"

    var name: String
    var startedAt: Date
    var endedAt: Date?
    /// Where the Show is. Nil when none was given, and in Shows from before venues.
    var venue: String?

    func write(to showFolder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: showFolder.appending(path: Self.fileName), options: .atomic)
    }

    /// The file in `showFolder`, or nil when it is missing or can't be read.
    static func read(from showFolder: URL) -> ShowFile? {
        guard let data = try? Data(contentsOf: showFolder.appending(path: fileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ShowFile.self, from: data)
    }
}

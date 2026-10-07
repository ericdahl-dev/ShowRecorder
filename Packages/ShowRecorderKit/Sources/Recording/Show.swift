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

    init(name: String, folder: URL, driveFolder: URL? = nil, takeCount: Int) {
        self.name = name
        self.folder = folder
        self.driveFolder = driveFolder
        self.takeCount = takeCount
    }

    /// Every Copy of the Show folder, the Device first.
    public var copies: [Show] {
        [Show(name: name, folder: folder, takeCount: takeCount)]
            + (driveFolder.map { [Show(name: name, folder: $0, takeCount: takeCount)] } ?? [])
    }

    /// Creates the Show folder on the Device (and on the Drive, if given), named "YYYY-MM-DD Show"
    /// from the start date. If that name is taken on either, a number is added ("… Show 2").
    static func create(in deviceParent: URL, drive driveParent: URL?, on date: Date) throws -> Show {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let base = String(format: "%04d-%02d-%02d Show", c.year ?? 0, c.month ?? 0, c.day ?? 0)
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
        var show = Show(name: name, folder: folder, takeCount: 0)
        try show.useDrive(driveParent)
        return show
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

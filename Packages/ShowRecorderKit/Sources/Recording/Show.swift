import Foundation

/// One event being recorded. Holds one or more Takes, each in its own folder.
public struct Show: Sendable, Equatable {
    public let name: String
    public let folder: URL
    public private(set) var takeCount: Int

    /// Creates the Show folder on the Device, named "YYYY-MM-DD Show" from the start date.
    /// If that folder already exists, a number is added ("… Show 2").
    static func create(in parent: URL, on date: Date) throws -> Show {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let base = String(format: "%04d-%02d-%02d Show", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let fm = FileManager.default
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        var name = base
        var suffix = 2
        while fm.fileExists(atPath: parent.appending(path: name).path) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        let folder = parent.appending(path: name, directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        return Show(name: name, folder: folder, takeCount: 0)
    }

    /// Creates "Take NN" for the next Take and returns its folder.
    mutating func createNextTakeFolder() throws -> URL {
        takeCount += 1
        let folder = folder.appending(path: String(format: "Take %02d", takeCount), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }
}

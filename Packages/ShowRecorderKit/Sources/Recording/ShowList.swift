import BroadcastWave
import Destinations
import Foundation

/// One line of the Show list.
public struct ShowSummary: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var folder: URL
    public var startedAt: Date
    public var takeCount: Int
    /// Seconds from the first Take's start to the last Take's end; 0 for a Show with no Take.
    public var duration: TimeInterval
    /// How the Copy stands, from its Takes' Gaps and Repairs; nil when the Copy isn't there.
    public var deviceCopy: CopyOutcome?
    public var driveCopy: CopyOutcome?
    /// Whether `Show.json` says a Drive Copy was ever created; nil when it doesn't say (older Shows).
    public var driveCopyWritten: Bool? = nil
    /// Whether the Drive was connected when the list was read.
    public var driveConnected = false

    /// The folder to hand to the share sheet or Files: the Device Copy, with its Stems, report and Reaper
    /// project. Nil when the Show is only on the Drive, which is a disk of its own.
    public var shareFolder: URL? { deviceCopy == nil ? nil : folder }
}

/// The one quiet line under a Show in the list, shown only when a Copy isn't complete.
public struct CopyNote: Equatable, Sendable {
    public enum Severity: Equatable, Sendable { case warning, problem }
    public var text: String
    public var severity: Severity
}

extension ShowSummary {
    /// What to say about the Copies, or nil when both are complete (or Repaired). Words as in CONTEXT.md.
    public var copyNote: CopyNote? {
        var parts: [(String, CopyNote.Severity)] = []
        func add(_ copy: String, _ outcome: CopyOutcome?, missing: String) {
            switch outcome {
            case nil: parts.append((missing, .warning))
            case .complete, .repaired: break
            case .hasGaps: parts.append(("\(copy) copy has Gaps", .problem))
            case .repairFailed: parts.append(("\(copy) Repair failed", .problem))
            }
        }
        add("Device", deviceCopy, missing: "No Device copy")
        let driveMissing: String
        if driveCopyWritten == true { driveMissing = driveConnected ? "Drive copy missing" : "Drive not connected now" }
        else { driveMissing = "No Drive copy" }
        add("Drive", driveCopy, missing: driveMissing)
        guard !parts.isEmpty else { return nil }
        return CopyNote(text: parts.map(\.0).joined(separator: " · "), severity: parts.contains { $0.1 == .problem } ? .problem : .warning)
    }
}

/// Reads the past Shows from the files, so it works for the Drive too and needs no database.
public enum ShowList {
    public static func read(device: URL, drive: URL?) -> [ShowSummary] {
        let fm = FileManager.default
        func names(in parent: URL?) -> [String] {
            guard let parent, let all = try? fm.contentsOfDirectory(atPath: parent.path) else { return [] }
            return all.filter { !$0.hasPrefix(".") && (try? parent.appending(path: $0).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        return Set(names(in: device) + names(in: drive)).map { name in
            let folder = device.appending(path: name, directoryHint: .isDirectory)
            let driveFolder = drive?.appending(path: name, directoryHint: .isDirectory)
            let takes = takeFolders(in: folder).isEmpty ? driveFolder.map(takeFolders(in:)) ?? [] : takeFolders(in: folder)
            let file = ShowFile.read(from: folder) ?? driveFolder.flatMap { ShowFile.read(from: $0) }
            let first = takes.map(\.start).min()
            let start = file?.startedAt ?? first ?? dateInName(name) ?? .distantPast
            return ShowSummary(
                name: name, folder: folder, startedAt: start, takeCount: takes.count,
                duration: takes.map(\.end).max().map { $0.timeIntervalSince(first ?? start) } ?? 0,
                deviceCopy: outcome(of: .device, in: folder),
                driveCopy: driveFolder.flatMap { outcome(of: .drive, in: $0) },
                driveCopyWritten: file?.driveCopyWritten ?? driveFolder.flatMap { ShowFile.read(from: $0)?.driveCopyWritten },
                driveConnected: drive != nil)
        }
        .sorted { ($0.startedAt, $0.name) > ($1.startedAt, $1.name) }
    }

    /// The date a "YYYY-MM-DD …" folder name starts with, at local midnight.
    private static func dateInName(_ name: String) -> Date? {
        let parts = name.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard name.prefix(10).count == 10, parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The worst outcome of `copy` over the Takes in `showFolder`; nil when the folder isn't there.
    private static func outcome(of copy: DestinationKind, in showFolder: URL) -> CopyOutcome? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: showFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        let order: [CopyOutcome] = [.complete, .repaired, .hasGaps, .repairFailed]
        return takeMetadata(in: showFolder).map { $0.take.outcome(ofCopy: copy) }.max { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! } ?? .complete
    }

    static func takeMetadata(in showFolder: URL) -> [(folder: URL, take: TakeMetadata)] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? FileManager.default.contentsOfDirectory(at: showFolder, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: TakeMetadata.fileName)),
                  let take = try? decoder.decode(TakeMetadata.self, from: data)
            else { return nil }
            return (folder, take)
        }
    }

    /// When each Take of a Show started and ended.
    private static func takeFolders(in showFolder: URL) -> [(start: Date, end: Date)] {
        takeMetadata(in: showFolder).map { folder, take in
            let frames = take.usbChannels.compactMap { try? StemLength.frameCount(at: folder.appending(path: $0.stemFile)) }.max() ?? 0
            let seconds = Double(frames) / Double(max(take.sampleRate, 1))
            return (take.startedAt, take.startedAt.addingTimeInterval(seconds))
        }
    }
}

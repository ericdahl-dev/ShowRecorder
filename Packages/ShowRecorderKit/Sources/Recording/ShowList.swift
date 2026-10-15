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
        func add(_ copy: DestinationKind, _ outcome: CopyOutcome?, missing: String) {
            switch outcome {
            case nil: parts.append((missing, .warning))
            case .complete, .repaired: break
            case .hasGaps: parts.append(("\(copy.name) copy \(CopyOutcome.hasGaps.word)", .problem))
            case .repairFailed: parts.append(("\(copy.name) \(CopyOutcome.repairFailed.word)", .problem))
            }
        }
        add(.device, deviceCopy, missing: "No Device copy")
        let driveMissing: String
        if driveCopyWritten == true { driveMissing = driveConnected ? "Drive copy missing" : "Drive not connected now" }
        else { driveMissing = "No Drive copy" }
        add(.drive, driveCopy, missing: driveMissing)
        guard !parts.isEmpty else { return nil }
        return CopyNote(text: parts.map(\.0).joined(separator: " · "), severity: parts.contains { $0.1 == .problem } ? .problem : .warning)
    }
}

/// Reads the past Shows from the files, so it works for the Drive too and needs no database.
public enum ShowList {
    /// What reading the Show list found: Shows (possibly none) or a folder that couldn't be read.
    public enum Result: Equatable, Sendable {
        case shows([ShowSummary])
        case unreadable
    }

    /// Like `read`, but says so when the Shows folder exists and can't be read, so "no Shows" and "can't read" differ.
    public static func load(device: URL, drive: URL?) -> Result {
        for folder in [device, drive].compactMap({ $0 }) where FileManager.default.fileExists(atPath: folder.path) {
            if (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) == nil { return .unreadable }
        }
        return .shows(read(device: device, drive: drive))
    }

    public static func read(device: URL, drive: URL?) -> [ShowSummary] {
        let fm = FileManager.default
        func names(in parent: URL?) -> [String] {
            guard let parent, let all = try? fm.contentsOfDirectory(atPath: parent.path) else { return [] }
            return all.filter { !$0.hasPrefix(".") && (try? parent.appending(path: $0).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        return Set(names(in: device) + names(in: drive)).map { name in
            let folder = device.appending(path: name, directoryHint: .isDirectory)
            let driveFolder = drive?.appending(path: name, directoryHint: .isDirectory)
            let takes = takeLengths(deviceShow: folder, driveShow: driveFolder).map { take, frames in
                (start: take.startedAt, end: take.startedAt.addingTimeInterval(Double(frames) / Double(max(take.sampleRate, 1))))
            }
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
        // A folder whose name starts with "." isn't a Take, such as one a move set aside (#630).
        let entries = ((try? FileManager.default.contentsOfDirectory(at: showFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        return entries.compactMap { folder in
            guard let take = try? TakeMetadata.read(fromTakeFolder: folder) else { return nil }
            return (folder, take)
        }
    }

    /// Each Take of a Show with its length in frames, from whichever Copy has it (#625). A Take whose Device `Take.json`
    /// has no stand-ins is read from the Device only, as before Drive only, and never falls back to the Drive. Under
    /// Drive only (ADR 0006) the Drive holds the audio: a Take with no Device folder is read from the Drive, and one the
    /// Device keeps only as stand-ins is as long as the longer of the Drive's Stems and its stand-ins, whose Stems cover
    /// only `start..<end`.
    static func takeLengths(deviceShow: URL, driveShow: URL?) -> [(take: TakeMetadata, frames: UInt64)] {
        func frames(_ folder: URL, _ take: TakeMetadata) -> UInt64 {
            take.usbChannels.compactMap { try? StemFile.inspect(folder.appending(path: $0.stemFile)).frameCount }.max() ?? 0
        }
        let device = takeMetadata(in: deviceShow)
        var lengths: [Int: (take: TakeMetadata, frames: UInt64)] = [:]
        for (folder, take) in device where take.standIns == nil { lengths[take.take] = (take, frames(folder, take)) }
        for (folder, take) in driveShow.map(takeMetadata(in:)) ?? [] where lengths[take.take] == nil {
            lengths[take.take] = (take, frames(folder, take))
        }
        for (_, take) in device {
            guard let standIns = take.standIns else { continue }
            let end = UInt64(clamping: standIns.map(\.end).max() ?? 0)
            lengths[take.take] = (take, max(lengths[take.take]?.frames ?? 0, end))
        }
        return lengths.values.sorted { $0.take.take < $1.take.take }
    }
}

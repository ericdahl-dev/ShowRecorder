import BroadcastWave
import Destinations
import Foundation
import TakeFile

/// Drive only (#656): a Take that can't move whole stays on this iPhone, and the operator may delete it by hand once the
/// Drive verifiably holds everything the Device holds of it. `verifyHeld` is that check, and it gates a delete of the Device's
/// only copy, so it trusts nothing the Take.json says about what is safe to skip. It is not `verifyTake`: it does not ask the
/// Drive to hold the whole Take, only the frames the Device really has.
///
/// - The Device's Take folder must hold nothing the Take.json doesn't list: no Stem of another channel, no stand-in folder
///   that isn't named, no other file. What isn't listed would be deleted unseen.
/// - Every audio piece the Device holds is compared with the Drive's Stem sample for sample: the root Stem's real length
///   (a cut-off Take's channels end at different lengths) and each stand-in's Stem where it sits in the Take, both at once if
///   both are there. A stand-in that holds nothing (`start == end`) must have empty Stems.
/// - A range the Take.json calls a Gap of the Device's own passes where the Device's bytes are silence or equal the Drive's:
///   a Gap that is stale or too big never hides audio.
/// - The Drive's Stem must be a regular file of its own, declare and hold every frame compared, and the two folders must be
///   the same recording (`takePairProblem`).
///
/// It reads every Stem, so run it off the main thread. Nothing is written.
extension CopyCheck {
    public static func verifyHeld(device: URL, drive: URL) -> Result {
        verifyHeld(device: device, drive: drive, shouldStop: { false }) ?? .failed([])
    }

    /// `verifyHeld` asking `shouldStop` between pieces of every Stem it reads: nil when it stopped, which is neither passed nor
    /// failed.
    static func verifyHeld(device: URL, drive: URL, shouldStop: () -> Bool) -> Result? {
        if let problem = takePairProblem(device: device, drive: drive) { return .failed([problem]) }
        guard let deviceTake = try? TakeMetadata.read(fromTakeFolder: device), let driveTake = try? TakeMetadata.read(fromTakeFolder: drive) else {
            return .failed(["\(device.lastPathComponent) can't be read."])
        }
        let name = TakeMetadata.name(take: deviceTake.take)
        let standIns = deviceTake.standIns ?? []
        guard standIns.allSatisfy({ $0.start >= 0 && $0.end >= $0.start }) else { return .failed(["\(name)'s Take.json lists a stand-in that can't be."]) }
        let ownGaps = deviceTake.gaps.filter { $0.copy == .device }
        guard ownGaps.allSatisfy({ $0.start >= 0 && $0.end >= $0.start }) else { return .failed(["\(name)'s Take.json lists a Gap that can't be."]) }
        if let problem = unlistedProblem(name, deviceTake, in: device) { return .failed([problem]) }

        var problems: [String] = []
        func note(_ problem: String) { if !problems.contains(problem) { problems.append(problem) } }
        let fm = FileManager.default
        for channel in deviceTake.usbChannels {
            let label = "\(name), channel \(channel.usbChannel)"
            guard let match = driveTake.usbChannels.first(where: { $0.usbChannel == channel.usbChannel }) else {
                note("\(label) is missing on the Drive.")
                continue
            }
            let driveURL = drive.appending(path: match.stemFile)
            guard isPlainName(match.stemFile), isRegularFile(driveURL), let driveStem = try? StemFile.inspect(driveURL) else {
                note("\(label) can't be read on the Drive.")
                continue
            }
            // What the Device holds of this channel: every piece, where it begins in the Take, how long it is.
            var pieces: [(url: URL, start: Int, frames: Int, gaps: [Range<Int>])] = []
            var unreadable = false
            let root = device.appending(path: channel.stemFile)
            if fm.fileExists(atPath: root.path) {
                if sameItem(root, driveURL) { note("\(label) is the same file on the Device and the Drive."); continue }
                if isRegularFile(root), let held = try? StemFile.inspect(root) {
                    pieces.append((root, 0, Int(held.framesOnDisk), ownGaps.map { $0.start..<$0.end }))
                } else {
                    unreadable = true
                }
            }
            for standIn in standIns {
                let url = device.appending(path: standIn.folderName).appending(path: channel.stemFile)
                let held = isRegularFile(url) ? try? StemFile.inspect(url) : nil
                if standIn.end == standIn.start {
                    // A stand-in that holds nothing: its Stems must hold nothing, or there is audio that no range names.
                    if let held, held.bytesOnDisk != 0 { unreadable = true }
                    continue
                }
                guard let held else { unreadable = true; continue }
                // All it holds, not only `end - start`: an abandoned standby's Stem can hold more than its end (#664, #871).
                pieces.append((url, standIn.start, Int(held.framesOnDisk), []))
            }
            if unreadable {
                note("\(label) can't be read on the Device.")
                continue
            }
            for piece in pieces where piece.frames > 0 {
                if piece.start + piece.frames > Int(min(driveStem.frameCount, driveStem.framesOnDisk)) {
                    note("\(label) is shorter on the Drive than what the Device holds.")
                    continue
                }
                let whole = piece.start..<(piece.start + piece.frames)
                let silent = piece.gaps.map { $0.clamped(to: whole) }.filter { !$0.isEmpty }
                let strict = CopyCoverage.subtracting(silent, from: whole)
                for (ranges, allowsSilence) in [(strict, false), (CopyCoverage.merged(silent), true)] {
                    for range in ranges {
                        switch sameSamples(
                            piece.url, deviceFrame: range.lowerBound - piece.start, driveURL, driveFrame: range.lowerBound,
                            frames: range.count, allowsSilence: allowsSilence, shouldStop: shouldStop
                        ) {
                        case nil: return nil
                        case false?: note("\(label) differs on the Drive from what the Device holds.")
                        case true?: break
                        }
                    }
                }
            }
        }
        return problems.isEmpty ? .passed : .failed(problems)
    }

    /// A stem file name that stays in its Take folder.
    private static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    /// Whether `url` is a regular file, not a link.
    private static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    /// Why the Device's Take folder holds something its Take.json doesn't list, if it does: that would be deleted unseen.
    private static func unlistedProblem(_ name: String, _ take: TakeMetadata, in device: URL) -> String? {
        let fm = FileManager.default
        let stems = Set(take.usbChannels.map(\.stemFile))
        let standIns = Set((take.standIns ?? []).map(\.folderName))
        guard let entries = try? fm.contentsOfDirectory(atPath: device.path) else { return "\(name) can't be read on the Device." }
        // The Finder's .DS_Store on macOS is no file of the Take's.
        // Nor is a Take.json a crash left staged (#914).
        for entry in entries where entry != TakeMetadata.fileName && entry != ".DS_Store" && !TakeJsonWriter.isStagingFile(entry) {
            let url = device.appending(path: entry)
            if standIns.contains(entry) {
                guard ShowDeleter.isRealFolder(url) else { return "\(name)'s stand-in isn't a folder of its own on the Device." }
                let files = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
                if !Set(files).subtracting([".DS_Store"]).isSubset(of: stems) { return "\(name)'s stand-in has files the Take doesn't list." }
            } else if !stems.contains(entry) {
                return "\(name) has files on the Device that its Take.json doesn't list."
            }
        }
        return nil
    }

    /// Whether `frames` samples of the Stem at `device`, from its `deviceFrame`, are the samples of the one at `drive` from its
    /// `driveFrame`, byte for byte. With `allowsSilence`, a stretch where the Device's bytes are all zero also counts: the Device
    /// holds no audio there. Samples that can't be read are never a match. Nil when stopped.
    private static func sameSamples(
        _ device: URL, deviceFrame: Int, _ drive: URL, driveFrame: Int, frames: Int, allowsSilence: Bool, shouldStop: () -> Bool
    ) -> Bool? {
        guard let a = try? StemFile.inspect(device), let b = try? StemFile.inspect(drive),
              let deviceHandle = try? FileHandle(forReadingFrom: device), let driveHandle = try? FileHandle(forReadingFrom: drive)
        else { return false }
        defer { try? deviceHandle.close(); try? driveHandle.close() }
        let bytesPerFrame = StemWriter.bytesPerSample
        var done = 0
        let chunkFrames = 262_144
        while done < frames {
            if shouldStop() { return nil }
            let count = min(chunkFrames, frames - done)
            do {
                try deviceHandle.seek(toOffset: a.dataStart + UInt64((deviceFrame + done) * bytesPerFrame))
                try driveHandle.seek(toOffset: b.dataStart + UInt64((driveFrame + done) * bytesPerFrame))
                guard let x = try deviceHandle.read(upToCount: count * bytesPerFrame), x.count == count * bytesPerFrame,
                      let y = try driveHandle.read(upToCount: count * bytesPerFrame)
                else { return false }
                if x != y, !(allowsSilence && !x.contains { $0 != 0 }) { return false }
            } catch {
                return false
            }
            done += count
        }
        return true
    }
}

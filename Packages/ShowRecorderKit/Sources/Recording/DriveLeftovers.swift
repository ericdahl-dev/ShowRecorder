import BroadcastWave
import Foundation
import TakeFile

/// Sweeps the Take folders a canceled or hung Drive join left on the Drive (#814).
///
/// A Drive that joins a running Take makes its Take folder and its Stems, and writes `Take.json` last. If Stop (or a
/// crash) comes first, the folder stays: empty, or with Stems that hold no audio, and no `Take.json`. Nothing refers to it.
///
/// Only a folder that is provably empty of audio goes, and only one that no Take could be using:
/// - named exactly "Take NN", with a number up to the Show's Take count when the sweep was asked for (a Take that starts
///   meanwhile has a higher one), and not touched for `grace` (a Take being made right now has just written to it);
/// - no `Take.json`, no subfolder, nothing but Stems (and the files a Finder leaves), every Stem without a sample (a file
///   that can't be read as a Stem counts only when it has no bytes at all);
/// - and not a Take the Device's `Take.json` marks as having an abandoned Drive Copy: `AbandonedCopyRecovery` repairs that
///   one from the Device, and needs its folder.
/// Anything else, a folder with a single sample in it, a note, a stand-in, stays.
enum DriveLeftovers {
    /// How long a folder must have been left alone before it counts as a leftover.
    static let grace: TimeInterval = 600

    /// Removes the leftover Take folders of the Show at `driveShow`, and returns their names, in order.
    @discardableResult
    static func sweep(driveShow: URL, deviceShow: URL, upTo takeCount: Int, now: Date = Date(), grace: TimeInterval = grace) -> [String] {
        let fm = FileManager.default
        var swept: [String] = []
        for name in ((try? fm.contentsOfDirectory(atPath: driveShow.path)) ?? []).sorted() {
            guard name.hasPrefix("Take "), let number = Int(name.dropFirst(5)), TakeMetadata.name(take: number) == name,
                  number <= takeCount else { continue }
            let folder = driveShow.appending(path: name, directoryHint: .isDirectory)
            // The recovery of an abandoned Drive Copy needs this folder, even if it holds nothing yet.
            let deviceTake = deviceShow.appending(path: name, directoryHint: .isDirectory)
            if fm.fileExists(atPath: deviceTake.path) {
                guard let metadata = try? TakeMetadata.read(fromTakeFolder: deviceTake), metadata.abandonedCopies == nil else { continue }
            }
            guard isOlder(folder, than: grace, at: now), isEmptyOfAudio(folder) else { continue }
            if removeLeftover(folder) { swept.append(name) }
        }
        return swept
    }

    /// Removes a folder judged to be a leftover, without ever removing more than that judgment covered: it takes out the
    /// empty Stems and Finder files one by one, then the directory itself with `rmdir`, which fails if anything else is in
    /// it. A `Take.json` (or a sample) that arrived after the judgment survives, and the folder with it. Returns whether the
    /// folder is gone.
    ///
    /// The grace period compares the Drive's own timestamps with this device's clock: a server far behind, or an exFAT mtime
    /// off by hours, can make a fresh folder look old. This is the guard that doesn't depend on that.
    static func removeLeftover(_ folder: URL) -> Bool {
        let fm = FileManager.default
        for entry in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
            let url = folder.appending(path: entry)
            if entry == ".DS_Store" || entry.hasPrefix("._") {
                try? fm.removeItem(at: url)
            } else if entry.hasSuffix(".wav"), isEmptyStem(url) {
                try? fm.removeItem(at: url)
            }
        }
        return rmdir(folder.path) == 0
    }

    /// Whether the file is a Stem with no samples (or no bytes at all).
    static func isEmptyStem(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return false }
        if let stem = try? StemFile.inspect(url) { return stem.bytesOnDisk == 0 }
        // Not readable as a Stem (a file created and never written, say): empty only if it has no bytes.
        let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.uint64Value
        return size == 0
    }

    /// Whether nothing in the folder, nor the folder, was made or changed in the last `grace` seconds.
    static func isOlder(_ folder: URL, than grace: TimeInterval, at now: Date) -> Bool {
        let fm = FileManager.default
        let entries = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
        for url in [folder] + entries {
            guard let attributes = try? fm.attributesOfItem(atPath: url.path) else { return false }
            let touched = [attributes[.creationDate] as? Date, attributes[.modificationDate] as? Date].compactMap { $0 }.max()
            guard let touched, now.timeIntervalSince(touched) >= grace else { return false }
        }
        return true
    }

    /// Whether the Take folder holds nothing but Stems with no samples. A folder that can't be read is not empty.
    static func isEmptyOfAudio(_ folder: URL) -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: folder.path) else { return false }
        for entry in entries {
            // What a Finder leaves is not audio, and not a reason to keep an empty folder.
            if entry == ".DS_Store" || entry.hasPrefix("._") { continue }
            // A Take.json, a stand-in folder, a note: something is referring to this folder, or someone put it there.
            guard entry.hasSuffix(".wav"), isEmptyStem(folder.appending(path: entry)) else { return false }
        }
        return true
    }
}

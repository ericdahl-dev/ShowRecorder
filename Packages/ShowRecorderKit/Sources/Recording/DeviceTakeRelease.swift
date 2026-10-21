import BroadcastWave
import Foundation
import TakeFile

/// Drive only (#656): deleting a kept Take from the Device by hand. A crashed Take the moves can't finish stays on the iPhone
/// with the reason; once `CopyCheck.verifyHeld` says the Drive holds everything the Device holds of it, the operator may delete
/// the Device's Take. Nothing is deleted without that choice, and never without the check:
///
/// 1. the check passes against the Device's Take;
/// 2. the Take is set aside (renamed, as a move does, so a crash here is finished or undone by `MoveRecovery`);
/// 3. the check passes again against what is set aside;
/// 4. only then it is removed. Any check that fails, or a Take started meanwhile, puts it back.
///
/// The Drive's Take is never written. Synchronous file I/O: call it off the main actor.
public enum DeviceTakeRelease {
    public enum Outcome: Equatable, Sendable {
        /// Removed from the Device; the Drive holds everything it held.
        case released
        /// Left on the Device, with why.
        case kept([String])
        /// A Take started: nothing is removed, or the set-aside Take was put back.
        case stopped
        /// The Device's Take was no longer there: nothing to do.
        case gone
    }

    /// What deleting would remove, for the confirmation: exactly what the Drive was just verified to hold.
    public struct Summary: Equatable, Sendable {
        public var take: Int
        /// USB Channels the Device's Take has.
        public var channels: Int
        /// Audio files on the Device the delete would remove: Stems, and the Stems of stand-ins.
        public var stems: Int
        /// Whether some of them are stand-ins.
        public var holdsStandIns: Bool
        /// The longest and the shortest audio a channel holds on the Device, in seconds (a cut-off Take's channels differ).
        public var longestSeconds: Double
        public var shortestSeconds: Double
    }

    public enum Check: Equatable, Sendable {
        case ok(Summary)
        case no([String])
        case stopped
    }

    /// Whether the Device's Take at `deviceTake` may be deleted: the Drive's at `driveTake` holds everything the Device holds
    /// of it. Reads every Stem; deletes nothing.
    static func check(deviceTake: URL, driveTake: URL, shouldStop: () -> Bool) -> Check {
        guard let result = CopyCheck.verifyHeld(device: deviceTake, drive: driveTake, shouldStop: shouldStop) else { return .stopped }
        if case .failed(let reasons) = result { return .no(reasons.isEmpty ? ["\(deviceTake.lastPathComponent) can't be checked."] : reasons) }
        guard let take = try? TakeMetadata.read(fromTakeFolder: deviceTake) else { return .no(["\(deviceTake.lastPathComponent) can't be read."]) }
        let rate = Double(max(take.sampleRate, 1))
        var stems = 0
        var seconds: [Double] = []
        for channel in take.usbChannels {
            var frames: UInt64 = 0
            let root = try? StemFile.inspect(deviceTake.appending(path: channel.stemFile))
            if let root { stems += 1; frames += root.framesOnDisk }
            for standIn in take.standIns ?? [] {
                if let held = try? StemFile.inspect(deviceTake.appending(path: standIn.folderName).appending(path: channel.stemFile)) {
                    stems += 1
                    frames += held.framesOnDisk
                }
            }
            seconds.append(Double(frames) / rate)
        }
        return .ok(Summary(
            take: take.take, channels: take.usbChannels.count, stems: stems, holdsStandIns: take.standIns?.isEmpty == false,
            longestSeconds: seconds.max() ?? 0, shortestSeconds: seconds.min() ?? 0))
    }

    /// Deletes the Device's Take at `deviceTake`, after the checks above. `shouldStop` is asked before the Take is set aside and
    /// between pieces of every Stem the checks read; `hook` lets tests act at a `Step`.
    static func run(deviceTake: URL, driveTake: URL, shouldStop: () -> Bool, at hook: (StandInMove.Step) -> Void = { _ in }) -> Outcome {
        let name = deviceTake.lastPathComponent
        let fm = FileManager.default
        guard fm.fileExists(atPath: deviceTake.path) else { return .gone }
        guard ShowDeleter.isRealFolder(deviceTake) else { return .kept(["\(name) isn't a folder of its own on the Device."]) }
        switch check(deviceTake: deviceTake, driveTake: driveTake, shouldStop: shouldStop) {
        case .stopped: return .stopped
        case .no(let reasons): return .kept(reasons)
        case .ok: break
        }
        if shouldStop() { return .stopped }

        let setAsideName = StandInMove.setAsideName(of: deviceTake)
        let setAside = deviceTake.deletingLastPathComponent().appending(path: setAsideName, directoryHint: .isDirectory)
        guard !fm.fileExists(atPath: setAside.path) else { return .kept(["A folder \(setAsideName) from an earlier move is in the way on the Device."]) }
        guard (try? fm.moveItem(at: deviceTake, to: setAside)) != nil else { return .kept(["\(name) couldn't be set aside on the Device."]) }
        hook(.setAside)
        // Once more, against what is now set aside, before anything is deleted. Stopped or failed, it is put back.
        let second = CopyCheck.verifyHeld(device: setAside, drive: driveTake, shouldStop: shouldStop)
        if second != .passed {
            var reasons: [String] = []
            if case .failed(let problems)? = second { reasons = problems }
            if fm.fileExists(atPath: deviceTake.path) || (try? fm.moveItem(at: setAside, to: deviceTake)) == nil {
                return .kept(reasons + ["\(name) couldn't be put back on the Device; it is in \(setAsideName)."])
            }
            return second == nil ? .stopped : .kept(reasons)
        }
        hook(.removing)
        guard (try? fm.removeItem(at: setAside)) != nil else {
            return .kept(["\(name) is on the Drive, but \(setAsideName) couldn't be removed from the Device."])
        }
        return .released
    }
}

extension DeviceTakeRelease.Summary {
    /// "Delete Take 03 from this iPhone?"
    public func title(deviceWord: String) -> String { "Delete \(TakeMetadata.name(take: take)) from this \(deviceWord)?" }

    /// What the Drive holds, what goes, that the Drive copy stays, and that it can't be undone on this device.
    public func message(deviceWord: String) -> String {
        let name = TakeMetadata.name(take: take)
        let count = stems == 1 ? "1 Stem" : "\(stems) Stems"
        let held = holdsStandIns ? ", including what this \(deviceWord) recorded while the Drive was away" : ""
        let lengths: String
        if stems == 1 || Int(longestSeconds) == Int(shortestSeconds) {
            lengths = stems == 1 ? ", \(Self.clock(longestSeconds)) long." : ", each \(Self.clock(longestSeconds)) long."
        } else {
            lengths = ", the longest \(Self.clock(longestSeconds)) and the shortest \(Self.clock(shortestSeconds))."
        }
        let goes = stems == 1 ? "that Stem" : "those \(stems) Stems"
        return "The Drive holds everything this \(deviceWord) holds of \(name): \(count)\(held)\(lengths) "
            + "Deleting removes \(goes) from this \(deviceWord). The Drive copy stays. This can't be undone on this \(deviceWord)."
    }

    /// 83 -> "1:23"; 3,725 -> "1:02:05".
    static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds)
        let (hours, minutes, rest) = (whole / 3_600, whole / 60 % 60, whole % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}

import BroadcastWave
import Destinations
import Foundation
import Synchronization
import TakeFile

/// Drive only (#196, ADR 0006, #630): moves a stand-in the Device kept into its Take on the Drive, then removes the
/// Device's Take. It fills only what the Drive is known to miss (its Gaps not yet repaired, and what it lacks past its
/// end), and removes nothing until `CopyCheck.verifyStandIn` passes, before and after the Device's Take is set aside.
/// Any check that fails keeps the stand-in where it is and says why.
enum StandInMove {
    enum Outcome: Equatable, Sendable {
        case moved
        /// Kept on the Device, with why.
        case kept([String])
        /// A Take started: the move stopped at a Stem boundary and left everything as a later move can take it up.
        case stopped
        /// The Device's Take was no longer there: nothing to do.
        case gone
    }

    /// Where a move is, for tests to act at.
    enum Step {
        /// The Device's Take was just set aside.
        case setAside
        /// Both checks passed; the set-aside folder is about to be removed.
        case removing
    }

    struct Result: Equatable, Sendable {
        var show: String
        var take: Int
        var outcome: Outcome
    }

    /// Set while a Take runs, so a move stops at the next Stem. Read off the main actor.
    final class StopSignal: Sendable {
        private let flag = Atomic<Bool>(false)
        var isSet: Bool { flag.load(ordering: .relaxed) }
        func set(_ value: Bool) { flag.store(value, ordering: .relaxed) }
    }

    /// The folder a move sets the Device's Take aside in before deleting it; readers skip names starting with ".".
    static func setAsideName(of take: URL) -> String { ".moved \(take.lastPathComponent)" }

    /// Moves the stand-in of the Device's Take at `deviceTake` into the Drive's at `driveTake`. Synchronous file I/O:
    /// call it off the main actor. `shouldStop` is asked before each Stem and before the Device's Take is set aside;
    /// `hook` lets tests act at a `Step`.
    static func run(deviceTake: URL, driveTake: URL, shouldStop: () -> Bool, at hook: (Step) -> Void = { _ in }) -> Outcome {
        let name = deviceTake.lastPathComponent
        let fm = FileManager.default
        guard fm.fileExists(atPath: deviceTake.path) else { return .gone }
        // Nothing is written to the Drive until both are checked to be the same recording, in folders of their own.
        if let problem = CopyCheck.standInProblem(deviceTake: deviceTake, driveTake: driveTake) { return .kept([problem]) }
        guard let device = try? TakeMetadata.read(fromTakeFolder: deviceTake), let standIns = device.standIns,
              var drive = try? TakeMetadata.read(fromTakeFolder: driveTake) else {
            return .kept(["\(name) can't be read."])
        }
        // Each channel's Stem on the Drive, found by USB Channel: a name changed on one Copy only stays as it is.
        var targets: [(channel: TakeMetadata.USBChannel, stem: URL)] = []
        for channel in device.usbChannels {
            guard let match = drive.usbChannels.first(where: { $0.usbChannel == channel.usbChannel }) else {
                return .kept(["\(name), channel \(channel.usbChannel) of the stand-in is missing on the Drive."])
            }
            let stem = driveTake.appending(path: match.stemFile)
            let values = try? stem.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                return .kept(["\(name), channel \(channel.usbChannel) isn't a Stem of its own on the Drive."])
            }
            // Appending from a stand-in needs the Drive's Stem to reach where it starts.
            let frames = Int((try? StemFile.inspect(stem))?.framesOnDisk ?? 0)
            guard standIns.allSatisfy({ frames >= $0.start }) else { return .kept(["\(name) on the Drive is missing audio before its stand-in."]) }
            targets.append((channel, stem))
        }
        // What the Drive is known to miss: the Gaps either Take records for it that the Drive hasn't had repaired.
        let gaps = drive.gaps + device.gaps.filter { !drive.gaps.contains($0) }
        let unrepaired = gaps.filter { gap in
            gap.copy == .drive && !drive.repairs.contains { $0.copy == .drive && $0.start == gap.start && $0.end == gap.end && $0.outcome == .repaired }
        }
        let markers = drive.markers.map { StemMarker(position: UInt32(clamping: $0.position), label: $0.name) }
        for (channel, stem) in targets {
            if shouldStop() { return .stopped }
            for standIn in standIns {
                let frames = Int((try? StemFile.inspect(stem))?.framesOnDisk ?? 0)
                let ranges = unrepaired.map { ($0.start..<$0.end).clamped(to: standIn.start..<standIn.end) }.filter { !$0.isEmpty }
                guard !ranges.isEmpty || frames < standIn.end else { continue }
                do {
                    try StemRepair.fill(
                        target: stem, from: deviceTake.appending(path: standIn.folderName).appending(path: channel.stemFile),
                        sourceStart: standIn.start, ranges: ranges, length: standIn.end, markers: markers)
                } catch {
                    return .kept(["\(name), channel \(channel.usbChannel) couldn't be written on the Drive."])
                }
            }
        }
        // Checked before any Repair is recorded, so a stand-in that doesn't hold all it lists is no false Repair.
        if case .failed(let reasons) = CopyCheck.verifyStandIn(deviceTake: deviceTake, driveTake: driveTake) { return .kept(reasons) }
        if !unrepaired.isEmpty {
            let filled = unrepaired.map { gap in
                TakeMetadata.Repair(
                    copy: .drive, start: gap.start, end: gap.end,
                    outcome: TakeRepair.covers(standIns.map { $0.start..<$0.end }, gap.start..<gap.end) ? .repaired : .failed)
            }
            drive.gaps = gaps
            drive.repairs = drive.repairs.filter { old in !filled.contains { $0.start == old.start && $0.end == old.end && $0.copy == old.copy } }
                + filled
            guard (try? drive.write(to: driveTake)) != nil else { return .kept(["\(name)'s Take.json couldn't be written on the Drive."]) }
            if filled.contains(where: { $0.outcome == .failed }) { return .kept(["\(name) has a Gap its stand-in doesn't hold."]) }
        }
        if shouldStop() { return .stopped }

        // The Device's Take holds its Take.json and stand-ins, nothing else that the move would delete with it.
        // The Finder's .DS_Store on macOS is no file of the Take's, and goes with it.
        let expected = Set([TakeMetadata.fileName, ".DS_Store"] + standIns.map(\.folderName))
        guard let contents = try? fm.contentsOfDirectory(atPath: deviceTake.path) else { return .kept(["\(name) can't be read on the Device."]) }
        let others = Set(contents).subtracting(expected)
        guard others.isEmpty else { return .kept(["\(name) on the Device holds other files too: \(others.sorted().joined(separator: ", "))."]) }

        let setAsideName = setAsideName(of: deviceTake)
        let setAside = deviceTake.deletingLastPathComponent().appending(path: setAsideName, directoryHint: .isDirectory)
        guard !fm.fileExists(atPath: setAside.path) else { return .kept(["A folder \(setAsideName) from an earlier move is in the way on the Device."]) }
        guard (try? fm.moveItem(at: deviceTake, to: setAside)) != nil else { return .kept(["\(name) couldn't be set aside on the Device."]) }
        hook(.setAside)
        func putBack(_ reasons: [String]) -> Outcome {
            if fm.fileExists(atPath: deviceTake.path) || (try? fm.moveItem(at: setAside, to: deviceTake)) == nil {
                return .kept(reasons + ["\(name) couldn't be put back on the Device; it is in \(setAsideName)."])
            }
            return .kept(reasons)
        }
        var cleared = drive
        cleared.standIns = nil
        guard (try? cleared.write(to: driveTake)) != nil else { return putBack(["\(name)'s Take.json couldn't be written on the Drive."]) }
        // Once more, against what is now set aside, before anything is deleted.
        if case .failed(let reasons) = CopyCheck.verifyStandIn(deviceTake: setAside, driveTake: driveTake) {
            let restored = (try? drive.write(to: driveTake)) != nil
            return putBack(reasons + (restored ? [] : ["\(name)'s stand-in couldn't be listed again in the Drive's Take.json."]))
        }
        hook(.removing)
        guard (try? fm.removeItem(at: setAside)) != nil else {
            return .kept(["\(name) is on the Drive, but \(setAsideName) couldn't be removed from the Device."])
        }
        return .moved
    }
}

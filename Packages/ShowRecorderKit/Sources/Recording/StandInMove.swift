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
        /// A Drive only Take's copy on the Drive was just filled from the Device (`DeviceTakeMove`).
        case filled
    }

    struct Result: Equatable, Sendable {
        var show: String
        var take: Int
        var outcome: Outcome
    }

    /// Counts the Takes started, so a move stops once one has, even if it has ended since. Read off the main actor.
    final class StopSignal: Sendable {
        private let takesStarted = Atomic<Int>(0)
        /// A Take started.
        func takeStarted() { takesStarted.add(1, ordering: .relaxed) }
        /// What a move asks: true from the first Take started after this call, for good.
        func latch() -> @Sendable () -> Bool {
            let started = takesStarted.load(ordering: .relaxed)
            return { [self] in takesStarted.load(ordering: .relaxed) != started }
        }
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
        // A Device Gap the Drive's own Gaps cover is known there already: a move splits a Gap on the Drive only (#916).
        let onDrive = drive.gaps.filter { $0.copy == .drive }.map { $0.start..<$0.end }
        let gaps = drive.gaps + device.gaps.filter { gap in
            !drive.gaps.contains(gap) && !(gap.copy == .drive && TakeRepair.covers(onDrive, gap.start..<gap.end))
        }
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
                        sourceStart: standIn.start, ranges: ranges, length: standIn.end, markers: markers, shouldStop: shouldStop)
                } catch is StemRepair.Stopped {
                    // Within the Stem: its Gaps stay unrepaired, for a later move.
                    return .stopped
                } catch {
                    return .kept(["\(name), channel \(channel.usbChannel) couldn't be written on the Drive."])
                }
            }
        }
        // Checked before any Repair is recorded, so a stand-in that doesn't hold all it lists is no false Repair.
        guard let check = CopyCheck.verifyStandIn(deviceTake: deviceTake, driveTake: driveTake, shouldStop: shouldStop) else { return .stopped }
        if case .failed(let reasons) = check { return .kept(reasons) }
        if !unrepaired.isEmpty {
            // Each Gap is split at the stand-ins' bounds: the part they hold is repaired, the rest stays a failed Gap of its
            // own, so a later move writes nothing it already wrote (#916).
            let held = standIns.map { $0.start..<$0.end }
            func filling(_ gap: TakeMetadata.Gap) -> [TakeMetadata.Repair] {
                pieces(of: gap.start..<gap.end, heldIn: held).map { part, isHeld in
                    .init(copy: .drive, start: part.lowerBound, end: part.upperBound, outcome: isHeld ? .repaired : .failed)
                }
            }
            let filled = unrepaired.flatMap(filling)
            // Each in its Gap's place, so a move that changes nothing writes the same lists. A Repair recorded over a whole
            // Gap (failed, or by an earlier version) gives way to its parts.
            drive.gaps = gaps.flatMap { gap in unrepaired.contains(gap) ? filling(gap).map { .init(copy: .drive, start: $0.start, end: $0.end) } : [gap] }
            var repairs = drive.repairs.flatMap { old in
                old.copy == .drive ? unrepaired.first { $0.start == old.start && $0.end == old.end }.map(filling) ?? [old] : [old]
            }
            for repair in filled where !repairs.contains(repair) { repairs.append(repair) }
            drive.repairs = repairs
            guard (try? drive.write(to: driveTake)) != nil else { return .kept(["\(name)'s Take.json couldn't be written on the Drive."]) }
            if filled.contains(where: { $0.outcome == .failed }) { return .kept(["\(name) has a Gap its stand-in doesn't hold."]) }
        }
        if shouldStop() { return .stopped }

        // The Device's Take holds its Take.json and stand-ins, nothing else that the move would delete with it.
        // The Finder's .DS_Store on macOS is no file of the Take's, and goes with it.
        let expected = Set([TakeMetadata.fileName, ".DS_Store"] + standIns.map(\.folderName))
        guard let contents = try? fm.contentsOfDirectory(atPath: deviceTake.path) else { return .kept(["\(name) can't be read on the Device."]) }
        // A staged Take.json a crash left (#914) is no file of the Take's either.
        let others = Set(contents).subtracting(expected).filter { !TakeJsonWriter.isStagingFile($0) }
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
        // Once more, against what is now set aside, before anything is deleted. Stopped, it is undone for a later move.
        let second = CopyCheck.verifyStandIn(deviceTake: setAside, driveTake: driveTake, shouldStop: shouldStop)
        if second == nil || second != .passed {
            let restored = (try? drive.write(to: driveTake)) != nil
            var reasons: [String] = []
            if case .failed(let problems) = second { reasons = problems }
            let outcome = putBack(reasons + (restored ? [] : ["\(name)'s stand-in couldn't be listed again in the Drive's Take.json."]))
            if second == nil, outcome == .kept([]) { return .stopped }
            return outcome
        }
        hook(.removing)
        guard (try? fm.removeItem(at: setAside)) != nil else {
            return .kept(["\(name) is on the Drive, but \(setAsideName) couldn't be removed from the Device."])
        }
        return .moved
    }

    /// `range` cut at the bounds of `held`, in order, each part with whether `held` covers it.
    private static func pieces(of range: Range<Int>, heldIn held: [Range<Int>]) -> [(Range<Int>, Bool)] {
        // An empty Gap stays one, held, as `TakeRepair.covers` says.
        guard !range.isEmpty else { return [(range, true)] }
        let bounds = Set([range.lowerBound, range.upperBound] + held.flatMap { [$0.lowerBound, $0.upperBound] }.filter { range.contains($0) }).sorted()
        var parts: [(Range<Int>, Bool)] = []
        for (start, end) in zip(bounds, bounds.dropFirst()) {
            let isHeld = TakeRepair.covers(held, start..<end)
            // Neighbors alike are one part.
            if let last = parts.last, last.1 == isHeld, last.0.upperBound == start {
                parts[parts.count - 1].0 = last.0.lowerBound..<end
            } else {
                parts.append((start..<end, isHeld))
            }
        }
        return parts
    }
}

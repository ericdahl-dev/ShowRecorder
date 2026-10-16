import BroadcastWave
import Destinations
import Foundation
import MixerLink

/// One Stem's file name and Source name, kept so a Copy that joins mid-Take can create the same Stems.
struct StemSpec {
    var file: String
    var description: String
    /// False for a USB Channel this Take doesn't record (Free records 2): it is captured like the others, so
    /// every channel stays in step, but its samples go nowhere and no file is made.
    var isRecorded = true
}

/// Where an unrecorded USB Channel's samples go: counted, never written.
final class DiscardingSink: StemSink {
    private(set) var frameCount: UInt64

    init(frameCount: UInt64 = 0) {
        self.frameCount = frameCount
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws { frameCount += UInt64(samples.count) }
    func commitHeader() throws {}
    func finalize() throws {}
    func setMarkers(_ markers: [StemMarker]) throws -> Int { markers.count }
}

/// The running Take's Copies. Owns one record per Copy (its folder, feed, writer and, for the Drive,
/// the access held for the Take) and everything that changes while the Take runs: Markers, Gaps,
/// a Drive joining or rejoining, a Copy retiring for lack of space. `Recorder` keeps Armed state and
/// decides when a Take starts and stops.
@MainActor
final class TakeSession {
    /// One Copy of the Take.
    struct CopyRecord {
        let kind: DestinationKind
        var folder: URL
        let feed: CopyFeed
        var writer: TakeWriter
        /// Gaps from this Copy's earlier writers, before a Drive rejoined.
        var earlierGaps: [Range<Int>] = []
        /// Held until the Take is finished and Repaired. Only the Drive has one.
        var access: DriveAccess?

        /// Stretches written as silence in this Copy because it joined after the Take began, as Take frames.
        var gaps: [Range<Int>] { earlierGaps + (writer.leadGap.map { [$0] } ?? []) }
    }

    /// What `checkDestinations` found.
    enum Check: Equatable {
        case carryOn
        /// The last healthy Copy is about to fill: the caller should end the Take.
        case outOfSpace
    }

    /// What Repair needs once the Take has ended.
    struct Finished: Sendable {
        var metadata: TakeMetadata
        var folders: [DestinationKind: URL]
        var access: DriveAccess?
        var signal: TakeSignal
        /// Copies Stop gave up on (#320): their files are left as they are, and Repair doesn't touch them.
        var abandoned: Set<DestinationKind> = []
    }

    /// How long Stop waits for each Copy's writer before giving it up (#320). Nil waits for ever.
    var stopTimeout: Duration?

    /// The open Show, which gains a Drive folder when the Drive joins.
    private(set) var show: Show
    private(set) var metadata: TakeMetadata
    private var levels: TakeLevels
    private(set) var copies: [CopyRecord] = []
    /// Called when any Copy's writer fails (on the main actor), so the owner can end the Take once none is left.
    var onCopyFailed: () -> Void = {}

    /// Drive only (#196, ADR 0006): the Device's standby, which holds the last seconds of the Take in memory and stands
    /// in for the Drive once it is lost. Nil for a Take with two Copies.
    private var standby: Standby?
    /// Drive only (#196, ADR 0006): the Take was started to be written to the Drive alone.
    let driveOnly: Bool
    /// How long the Drive's writer may go without writing while audio arrives before it counts as lost (a pulled
    /// Drive can hang rather than fail).
    var driveStallLimit: Duration = .seconds(2)
    /// The Drive writer's frames when it was last seen moving, and when.
    private var driveProgress: (frames: Int, at: ContinuousClock.Instant)?

    struct Standby {
        let folder: URL
        let feed: CopyFeed
        let writer: TakeWriter
        let sinks: [StandInSink]
        /// Where the stand-in starts, once the Drive is lost.
        var start: Int?
    }

    private let capture: Capture
    private let stems: [StemSpec]
    private let info: StemWriter.Info
    private let makeStem: (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink
    private let freeSpace: (URL) -> Int64

    /// Opens the Stems in each of `folders` (one per Copy, keyed by its kind), writes `Take.json` there
    /// and starts capturing. `drive` is the access held for the Drive Copy, when there is one.
    init(
        show: Show, folders: [DestinationKind: URL], drive: DriveAccess?, metadata: TakeMetadata, stems: [StemSpec],
        info: StemWriter.Info, capture: Capture, preRollFrames: Int = 0,
        makeStem: @escaping (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink,
        freeSpace: @escaping (URL) -> Int64, driveOnly: Bool = false
    ) throws {
        self.show = show
        var metadata = metadata
        // Every Copy's Take.json says the Take is Drive only, so one left on the Device can be found and moved (#630).
        if driveOnly { metadata.driveOnly = true }
        self.metadata = metadata
        levels = TakeLevels(channelCount: capture.channelCount)
        self.stems = stems
        self.info = info
        self.capture = capture
        self.makeStem = makeStem
        self.freeSpace = freeSpace
        self.driveOnly = driveOnly

        // One writer per Copy, each draining its own ring, so a slow Drive never holds up the Device.
        // With Pre-roll each Copy waits for the real-time thread's first block, then writes the Pre-roll
        // before the live audio.
        let head: (() -> [[Float]]?)? = preRollFrames > 0 && capture.preRoll != nil
            ? { [capture] in
                let start = capture.preRollStart.load(ordering: .acquiring)
                guard start >= preRollFrames else { return nil }
                return capture.preRoll?.read(frames: (start - preRollFrames)..<start)
            } : nil
        var records: [CopyRecord] = []
        precondition(DestinationKind.allCases.count <= capture.feeds.count, "more Copy kinds than Capture feeds")
        // Each Copy's feed, paired with its kind in order: Capture's feeds, like the kinds, put the Device first.
        let feeds = Dictionary(uniqueKeysWithValues: zip(DestinationKind.allCases, capture.feeds))
        // Drive only, with a Drive: the Device's ring feeds the standby, which writes nothing until the Drive is lost.
        let standingBy = driveOnly && folders[.device] != nil && folders[.drive] != nil
        if standingBy {
            let held = Int(Double(info.sampleRate) * Self.standbySeconds)
            // An unrecorded USB Channel is never stood in for, so it holds nothing.
            let sinks = stems.map { StandInSink(heldFrames: $0.isRecorded ? held : 1) }
            let feed = feeds[.device]!
            let writer = TakeWriter(feed: feed, stems: sinks, commitInterval: info.sampleRate * 2, onFailure: { [weak self, capture] in
                capture.stopFeeding(feed)
                Task { @MainActor in self?.onCopyFailed() }
            }, head: head)
            standby = Standby(folder: folders[.device]!, feed: feed, writer: writer, sinks: sinks)
        }
        for kind in DestinationKind.allCases where !(standingBy && kind == .device) {
            guard let folder = folders[kind] else { continue }
            let feed = feeds[kind]!
            let sinks: [any StemSink] = try stems.map { spec in
                spec.isRecorded ? try makeStem(folder.appending(path: spec.file), info.described(spec.description), nil) : DiscardingSink()
            }
            try metadata.write(to: folder)
            records.append(CopyRecord(
                kind: kind, folder: folder, feed: feed,
                writer: makeWriter(feed: feed, stems: sinks, head: head),
                access: kind == .drive ? drive : nil))
        }
        for record in records {
            capture.begin(record.feed, joinedAt: head == nil ? 0 : nil)
            record.writer.start()
        }
        if let standby {
            capture.begin(standby.feed, joinedAt: head == nil ? 0 : nil)
            standby.writer.start()
        }
        copies = records
        capture.startCapturing(copies: folders.count, preRollFrames: head == nil ? 0 : preRollFrames)
    }

    /// How much of the Take the standby holds: the Drive's ring (4 s), the time to notice it is lost and a margin.
    static let standbySeconds = 10.0

    /// Places a Marker at the Take's current sample position (frames written so far), in every Stem
    /// of every Copy and in `Take.json`.
    @discardableResult
    func addMarker(named name: String? = nil) -> TakeMetadata.Marker {
        let marker = TakeMetadata.Marker(
            position: capture.takeFrameCount, name: name.map { NameLimit.cut($0) } ?? metadata.nextMarkerName, origin: .operator)
        metadata.markers.append(marker)
        // Take.json first: it's written whole and atomically, so a Marker survives even if the Stems'
        // next header commit never happens.
        writeMetadata()
        for copy in copies { copy.writer.setMarkers(stemMarkers) }
        standby?.writer.setMarkers(stemMarkers)
        return marker
    }

    /// Logs a gain change on the Mixer at the Take's current sample position, in `Take.json` of every Copy, with a
    /// Marker named `markerName` there (not a cue in the Stems: only the operator's Markers are).
    func logGainChange(_ change: TakeMetadata.GainChange, markerName: String) {
        var change = change
        change.position = capture.takeFrameCount
        metadata.gainChanges = (metadata.gainChanges ?? []) + [change]
        metadata.markers.append(.init(position: capture.takeFrameCount, name: markerName, origin: .gain))
        writeMetadata()
    }

    /// The name of USB Channel `usbChannel` in this Take ("Kick", or "USB 01").
    func channelName(_ usbChannel: Int) -> String? {
        metadata.usbChannels.first { $0.usbChannel == usbChannel }?.name
    }

    /// Logs that the Mixer re-patched a USB Channel (#21), at the Take's current sample position, with a Marker in
    /// `Take.json` and in every Stem's cue points. Touches no audio: the Stem goes on with the new Source.
    ///
    /// A re-patch of the same USB Channel within a second of the last one (stepping the desk's source selector) only
    /// moves that change on to the new Source, so a sweep is one change and one Marker.
    func logRoutingChange(usbChannel: Int, from: String, to: String) {
        let position = capture.takeFrameCount
        var changes = metadata.routingChanges ?? []
        if let last = changes.lastIndex(where: { $0.usbChannel == usbChannel }),
           position - changes[last].position < metadata.sampleRate,
           let marker = metadata.markers.lastIndex(where: {
               $0.origin == .routing && $0.position == changes[last].position
                   && $0.name == RoutingChangeNotice.markerName(usbChannel: usbChannel, from: changes[last].from, to: changes[last].to)
           }) {
            changes[last].to = to
            metadata.markers[marker].name = RoutingChangeNotice.markerName(usbChannel: usbChannel, from: changes[last].from, to: to)
        } else {
            changes.append(.init(position: position, usbChannel: usbChannel, from: from, to: to))
            metadata.markers.append(.init(position: position, name: RoutingChangeNotice.markerName(usbChannel: usbChannel, from: from, to: to),
                                          origin: .routing))
        }
        metadata.routingChanges = changes
        writeMetadata()
        for copy in copies { copy.writer.setMarkers(stemMarkers) }
        standby?.writer.setMarkers(stemMarkers)
    }

    /// Logs that a Mixer renamed a Source, at the Take's current sample position, in `Take.json` of every
    /// Copy. Touches no audio and no Stem.
    func logRename(usbChannel: Int, from: String, to: String) {
        metadata.renames = (metadata.renames ?? []) + [.init(position: capture.takeFrameCount, usbChannel: usbChannel, from: from, to: to)]
        writeMetadata()
    }

    /// Renames the operator Marker at `index` (counting operator Markers only, in the order of
    /// `Recorder.takeMarkers`), in `Take.json` and in the Stems' cue labels.
    func renameMarker(at index: Int, to name: String) -> MarkerRename {
        let name = NameLimit.cut(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !name.isEmpty else { return .emptyName }
        guard let place = metadata.place(ofOperatorMarker: index) else { return .noSuchMarker }
        metadata.markers[place].name = name
        writeMetadata()
        for copy in copies { copy.writer.setMarkers(stemMarkers) }
        standby?.writer.setMarkers(stemMarkers)
        return .renamed
    }

    /// How `kind`'s Copy is doing. A Copy that never started is missing.
    func status(_ kind: DestinationKind) -> CopyState {
        if kind == .device, let standby, standby.start != nil { return standby.writer.hasFailed ? .interrupted : .recording }
        guard let copy = copies.first(where: { $0.kind == kind }) else { return .missing }
        return copy.writer.hasFailed ? .interrupted : .recording
    }

    /// Copies of the running Take (#550), from each Copy's status.
    var takeCopies: TakeCopies {
        TakeCopies(isRunning: true, isDriveOnly: driveOnly) { kind in
            if kind == .device, let standby {
                if standby.start == nil { return .standingBy }
                return standby.writer.hasFailed ? .interrupted : .standingIn
            }
            return status(kind)
        }
    }

    /// How many places in the Take lost audio (one Dropout Marker each).
    var dropoutCount: Int { metadata.dropoutCount }

    /// Whether every Copy's writer has failed, so there is nowhere left to record.
    var allFailed: Bool {
        // A Drive only Take's standby can still stand in for the Drive.
        if let standby, !standby.writer.hasFailed { return false }
        return !copies.isEmpty && copies.allSatisfy { $0.writer.hasFailed }
    }

    /// What each Copy holds so far, from its writer: the one source of Gaps and Dropouts (#441). A Copy that failed,
    /// retired or never joined stopped early, so it lacks everything past where it got to.
    private var coverage: CopyCoverage { Self.coverage(copies: copies, standby: standby) }

    nonisolated private static func coverage(copies: [CopyRecord], standby: Standby?) -> CopyCoverage {
        var all = copies.map { copy in
            CopyCoverage.Copy(
                // A Drive that went away may have lost what it wrote since its last commit (#595); a Device keeps it.
                kind: copy.kind, written: copy.kind == .drive ? copy.writer.framesKept : copy.writer.framesWritten,
                dropped: copy.writer.dropouts,
                silence: copy.gaps, stoppedEarly: copy.writer.hasFailed || copy.writer.neverJoined)
        }
        // Drive only: the standby holds the audio from where its stand-in starts, and nothing before.
        if let standby {
            let start = standby.start ?? Int.max
            all.insert(CopyCoverage.Copy(
                kind: .device, written: standby.start == nil ? 0 : standby.writer.framesWritten, dropped: standby.writer.dropouts,
                silence: [0..<min(start, standby.writer.framesWritten)],
                stoppedEarly: standby.start == nil || standby.writer.hasFailed || standby.writer.neverJoined), at: 0)
        }
        return CopyCoverage(all)
    }

    /// Stretches written as silence in any Copy, as `Take.json` records them. With `takeEnd`, a Copy that stopped
    /// early is missing everything from where it stopped to there.
    func gaps(takeEnd: Int? = nil) -> [TakeMetadata.Gap] { Self.gaps(copies: copies, standby: standby, takeEnd: takeEnd) }

    nonisolated private static func gaps(copies: [CopyRecord], standby: Standby?, takeEnd: Int?) -> [TakeMetadata.Gap] {
        // A Drive only Take has no Device Copy to have Gaps in: the standby only stands in.
        coverage(copies: copies, standby: standby).gaps(takeEnd: takeEnd).filter { standby == nil || $0.copy != .device }
    }

    /// Looks for a Destination that has become available since the Take started. A Drive that appears
    /// joins the running Take: its Stems start with silence up to the join point, which is recorded as
    /// a Gap in `Take.json` on both Copies. A Drive Copy that failed rejoins the same way when its
    /// Destination comes back. A Copy that is low on space retires; when the last healthy one is, this
    /// returns `.outOfSpace` and leaves the Take running for the caller to finish.
    ///
    /// `drive` is asked only when a Drive could join or rejoin, and each access it returns is either
    /// kept for the Take or released here.
    func checkDestinations(drive: () -> DriveAccess?) -> Check {
        // Keep 60 s of audio free on each Destination. A Copy that's short stops cleanly while another
        // has room; when the last healthy one is short the Take finalizes, before anything fills.
        let reserve = SpaceReserve(channelCount: metadata.usbChannels.count, sampleRate: info.sampleRate)
        let healthy = copies.filter { !$0.writer.hasFailed }
        let low = healthy.filter { reserve.isLow(free: freeSpace($0.folder)) }
        if !low.isEmpty {
            if low.count == healthy.count { return .outOfSpace }
            for copy in low {
                capture.stopFeeding(copy.feed)
                copy.writer.retire()
            }
        }
        if let standby {
            // A stand-in keeps the Device's space reserve like a Copy: short of it, it stops cleanly; when the Drive
            // is gone too, the Take ends.
            if standby.start != nil, !standby.writer.hasFailed, reserve.isLow(free: freeSpace(standby.folder)) {
                if healthy.isEmpty { return .outOfSpace }
                capture.stopFeeding(standby.feed)
                standby.writer.retire()
            }
            standInIfDriveLost()
        } else {
            let driveCopy = copies.first { $0.kind == .drive }
            if driveCopy == nil, let access = drive() {
                attachDrive(access, replacing: nil, reserve: reserve)
            }
            if let driveCopy, driveCopy.writer.isFinished, driveCopy.writer.hasFailed, let access = drive() {
                attachDrive(access, replacing: driveCopy, reserve: reserve)
            }
        }
        collectDropouts()
        persistGaps()
        return .carryOn
    }

    /// Adds the windows the meter read to the Take's levels. Written into `Take.json` when the Take finishes.
    func accumulate(_ windows: [ChannelLevel]) {
        levels.add(windows)
    }

    /// Stops capturing, waits until every Stem is written and finalized and records the Gaps.
    /// A Copy that failed during the Take doesn't make this throw.
    func finish() -> Finished {
        let finished = Self.finish(finishInput())
        adopt(finished)
        return finished
    }

    /// The snapshot `finish` works on (see `FinishInput` for when to take it).
    func finishInput() -> FinishInput {
        FinishInput(capture: capture, copies: copies, standby: standby, metadata: metadata, levels: levels, stopTimeout: stopTimeout)
    }

    /// Writes what `finish(_:)` came to back into the session.
    func adopt(_ finished: Finished) {
        metadata = finished.metadata
    }

    /// What `finish` works on, copied out of the session so the join and the file writes need no main actor (#652).
    /// A snapshot: take it after the last `accumulate`, after `Recorder` has dropped the session and canceled the
    /// destination checks (a late `attachDrive` or stand-in would be missing from it), and change nothing on the session
    /// until `finish()` writes the metadata back.
    struct FinishInput: Sendable {
        let capture: Capture
        let copies: [CopyRecord]
        let standby: Standby?
        var metadata: TakeMetadata
        let levels: TakeLevels
        let stopTimeout: Duration?
    }

    nonisolated static func finish(_ input: FinishInput) -> Finished {
        let capture = input.capture, copies = input.copies, standby = input.standby, levels = input.levels
        var metadata = input.metadata
        capture.stopCapturing()
        // Every writer is told to stop first, then all are waited on against one deadline, so two stuck Copies
        // hold Stop for one timeout, not two (#652). The deadline is taken after every stop request, so each writer
        // still gets the full timeout from its own request (#320).
        for copy in copies { copy.writer.requestStop() }
        standby?.writer.requestStop()
        let deadline = input.stopTimeout.map(TakeWriter.deadline)
        for copy in copies { copy.writer.waitStopped(until: deadline) }
        standby?.writer.waitStopped(until: deadline)
        // A standby is a Copy only if it stood in or its folder is kept: its empty folder isn't one, even if removing it fails.
        var standbyFolder = standby?.folder
        if let standby {
            if let start = standby.start {
                metadata.standIns = [.init(start: start, end: max(start, standby.writer.framesWritten))]
            } else if (try? FileManager.default.contentsOfDirectory(atPath: standby.folder.path).isEmpty) == true {
                // The Drive took the whole Take: the Device's Take folder this press made stays empty, so it goes.
                try? FileManager.default.removeItem(at: standby.folder)
                standbyFolder = nil
            }
        }
        collectDropouts(&metadata, copies: copies, standby: standby)
        // Levels are kept per captured channel; Take.json lists only the recorded ones, by USB Channel number.
        for (channel, summary) in levels.summary.enumerated() {
            guard let index = metadata.usbChannels.firstIndex(where: { $0.usbChannel == channel + 1 }) else { continue }
            metadata.usbChannels[index].peakDbfs = summary.peakDbfs
            metadata.usbChannels[index].averageDbfs = summary.averageDbfs
        }
        writeMetadata(metadata, copies: copies, standby: standby)
        // A Take whose Copies were never fed a first block is empty, not missing everything.
        persistGaps(&metadata, copies: copies, standby: standby, takeEnd: capture.awaitingFirstBlock ? 0 : capture.takeFrameCount)
        var folders: [DestinationKind: URL] = [:]
        folders[.device] = standbyFolder
        for copy in copies { folders[copy.kind] = copy.folder }
        return Finished(
            metadata: metadata, folders: folders, access: copies.lazy.compactMap(\.access).first,
            signal: TakeSignal(recorded: metadata.usbChannels.count, withSignal: levels.channelsWithSignal(), loudest: levels.loudest()),
            abandoned: Set(copies.filter { $0.writer.wasAbandoned }.map(\.kind)))
    }

    // MARK: - Drive join and rejoin

    /// Starts the Drive Copy, or restarts it over `old`. Both start new Stems in a Take folder under
    /// `access` and bring the Copy in through the same handshake; they differ in where the folder
    /// comes from, whether the Stems resume `old`'s and what happens to `old`'s access.
    private func attachDrive(_ access: DriveAccess, replacing old: CopyRecord?, reserve: SpaceReserve) {
        var show = show
        do {
            let folder: URL
            if old == nil {
                guard !reserve.isLow(free: freeSpace(access.folder)) else { access.end(); return }
                folder = try show.joinDrive(access.folder)
            } else {
                // The Drive may have come back at a different path (a remount), so find the Take folder
                // under the folder we were just given.
                folder = access.folder
                    .appending(path: show.name, directoryHint: .isDirectory)
                    .appending(path: TakeMetadata.name(take: show.takeCount), directoryHint: .isDirectory)
                guard FileManager.default.fileExists(atPath: folder.path), !reserve.isLow(free: freeSpace(folder)) else {
                    access.end()
                    return
                }
                try show.useDrive(access.folder)
            }
            // Each Stem resumes at its last commit (#595): what was written after it may never have reached the Drive,
            // so it is cut off and left to Repair. A Drive that failed but stayed mounted loses that stretch too, until
            // resuming at the frames really on disk (#602).
            let counts = old?.writer.stemFramesKept
            let sinks: [any StemSink] = try stems.enumerated().map { index, spec in
                spec.isRecorded
                    ? try makeStem(folder.appending(path: spec.file), info.described(spec.description), counts?[index])
                    : DiscardingSink(frameCount: counts?[index] ?? 0)
            }
            // A Take folder that was rejoined already has its Take.json.
            if old == nil { try metadata.write(to: folder) }

            // The Drive uses its kind's feed. A Drive joins for the first time only beside the Device.
            assert(old != nil || copies.count == 1, "a Drive joining beside more than the Device")
            let feed = old?.feed ?? capture.feeds[DestinationKind.drive.index]
            let writer = makeWriter(feed: feed, stems: sinks, markers: stemMarkers)
            capture.attachMidTake(feed)
            writer.start()
            // The rejoin's own Gap starts where the Stems resume, so earlier Gaps stop there (#595).
            let resume = Int(counts?.min() ?? 0)
            let earlierGaps = (old?.gaps ?? []).filter { $0.lowerBound < resume }.map { $0.clamped(to: 0..<resume) }

            let record = CopyRecord(kind: .drive, folder: folder, feed: feed, writer: writer, earlierGaps: earlierGaps, access: access)
            if old == nil { copies.append(record) } else if let i = copies.firstIndex(where: { $0.kind == .drive }) { copies[i] = record }
            old?.access?.end()
            self.show = show
        } catch {
            access.end()
        }
    }

    // MARK: - Helpers

    private func makeWriter(
        feed: CopyFeed, stems sinks: [any StemSink], head: (() -> [[Float]]?)? = nil, markers: [StemMarker] = []
    ) -> TakeWriter {
        TakeWriter(feed: feed, stems: sinks, commitInterval: info.sampleRate * 2, onFailure: { [weak self, capture] in
            capture.stopFeeding(feed)
            Task { @MainActor in self?.onCopyFailed() }
        }, head: head, markers: markers)
    }

    /// The Markers the Stems carry as cue points. Each writer adds its own Dropout Markers.
    private var stemMarkers: [StemMarker] {
        metadata.stemCueMarkers.map { StemMarker(position: UInt32(clamping: $0.position), label: $0.name) }
    }

    private func writeMetadata() { Self.writeMetadata(metadata, copies: copies, standby: standby) }

    nonisolated private static func writeMetadata(_ metadata: TakeMetadata, copies: [CopyRecord], standby: Standby?) {
        // A Copy Stop gave up on (set only at Stop) may hang on any file operation: Repair writes its Take.json off the main thread (#652).
        for copy in copies where !copy.writer.wasAbandoned { try? metadata.write(to: copy.folder) }
        // A stand-in's Take.json lets a crash mid-Take find it (and Repair it) on the next launch.
        if let standby, standby.start != nil { try? metadata.write(to: standby.folder) }
    }

    // MARK: - Drive only

    /// Starts the stand-in once the Drive falters: its writer failed, wrote nothing for `driveStallLimit` while audio
    /// arrived (a pulled Drive can hang rather than fail), or its ring overflowed (too slow to keep up).
    private func standInIfDriveLost() {
        guard var standby, standby.start == nil, !capture.awaitingFirstBlock,
              let drive = copies.first(where: { $0.kind == .drive }) else { return }
        let written = drive.writer.framesWritten
        let now = ContinuousClock.now
        var stalled = false
        if !drive.writer.hasFailed {
            if let last = driveProgress, last.frames == written {
                stalled = now - last.at >= driveStallLimit && capture.takeFrameCount > written
            } else {
                driveProgress = (written, now)
            }
        }
        // A Drive too slow to keep up drops audio but carries on: the standby stands in for it from the first drop,
        // and the Drive isn't given up, so Repair can fill it later.
        // The ring's overflow shows at once; the writer only logs the Dropout once it wakes, which a stuck write delays.
        let overflowed = drive.feed.ring.overflowedFrames.load(ordering: .relaxed) > 0
        let firstDrop = drive.writer.dropouts.map(\.lowerBound).min()
        guard drive.writer.hasFailed || stalled || overflowed || firstDrop != nil else { return }
        // A stalled Drive isn't given up: one that only paused (waking up, a busy moment) carries on, and Repair fills
        // what it dropped from the stand-in. One that never comes back is abandoned at Stop, which never waits on it
        // longer than `stopTimeout` (#320).
        // The earliest frame the standby will still hold when its writer next appends: a tenth of a second of margin
        // for the blocks that arrive meanwhile. Audio the Drive lost before that stays a Gap no stand-in covers.
        let held = Int(Double(info.sampleRate) * Self.standbySeconds)
        let newest = standby.sinks.map { Int($0.frameCount) }.max() ?? 0
        // From where the Drive stopped, less what it may not have made durable: up to one header commit (2 s) of
        // audio can die with a pulled Drive. The overlap costs nothing; Repair only fills Gaps.
        let lostFrom = min(written - info.sampleRate * 2, firstDrop ?? .max)
        let start = max(lostFrom, newest + info.sampleRate / 10 - held, 0)
        let folder = standby.folder.appending(path: TakeMetadata.StandIn(start: start, end: start).folderName, directoryHint: .isDirectory)
        var startInfo = info
        startInfo.timeReference += UInt64(start)
        for (spec, sink) in zip(stems, standby.sinks) where spec.isRecorded {
            let url = folder.appending(path: spec.file)
            let stemInfo = startInfo.described(spec.description)
            sink.standIn(from: start) { [makeStem] in
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return try makeStem(url, stemInfo, nil)
            }
        }
        standby.start = start
        self.standby = standby
        metadata.standIns = [.init(start: start, end: start)]
        writeMetadata()
    }

    /// Moves the audio the writers had to drop into `Take.json` as Dropouts (one per Copy and stretch), with
    /// one Dropout Marker at each position where any Copy lost audio.
    private func collectDropouts() { Self.collectDropouts(&metadata, copies: copies, standby: standby) }

    nonisolated private static func collectDropouts(_ metadata: inout TakeMetadata, copies: [CopyRecord], standby: Standby?) {
        // Only audio every Copy lacks; a stretch another Copy has is a Gap (see `gaps(takeEnd:)`).
        let found = coverage(copies: copies, standby: standby).dropouts
        guard found != metadata.dropouts else { return }
        let marked = Set(metadata.dropoutMarkers.map(\.position))
        for position in Set(found.map(\.start)).subtracting(marked).sorted() {
            metadata.markers.append(.init(position: position, name: "Dropout", origin: .dropout))
        }
        metadata.dropouts = found
        writeMetadata(metadata, copies: copies, standby: standby)
    }

    /// Writes the Gaps found so far into `Take.json` in every Copy.
    private func persistGaps(takeEnd: Int? = nil) { Self.persistGaps(&metadata, copies: copies, standby: standby, takeEnd: takeEnd) }

    nonisolated private static func persistGaps(
        _ metadata: inout TakeMetadata, copies: [CopyRecord], standby: Standby?, takeEnd: Int?
    ) {
        let gaps = gaps(copies: copies, standby: standby, takeEnd: takeEnd)
        guard gaps != metadata.gaps else { return }
        metadata.gaps = gaps
        writeMetadata(metadata, copies: copies, standby: standby)
    }
}

/// What came of renaming a Marker.
public enum MarkerRename: Equatable, Sendable {
    case renamed
    /// No Take is running.
    case notRecording
    /// There is no operator Marker at that index.
    case noSuchMarker
    /// The new name is empty or only whitespace.
    case emptyName
    /// Renaming from files: no Copy could be reached or read, so nothing was renamed.
    case noCopyUpdated
}

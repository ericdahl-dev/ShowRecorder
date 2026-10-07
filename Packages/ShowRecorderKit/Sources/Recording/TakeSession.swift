import BroadcastWave
import Destinations
import Foundation
import MixerLink

/// One Stem's file name and Source name, kept so a Copy that joins mid-Take can create the same Stems.
struct StemSpec {
    var file: String
    var description: String
}

/// The running Take's Copies. Owns one record per Copy (its folder, ring, writer and, for the Drive,
/// the access held for the Take) and everything that changes while the Take runs: Markers, Gaps,
/// a Drive joining or rejoining, a Copy retiring for lack of space. `Recorder` keeps Armed state and
/// decides when a Take starts and stops.
@MainActor
final class TakeSession {
    /// One Copy of the Take.
    struct CopyRecord {
        let kind: DestinationKind
        var folder: URL
        let ring: SampleRing
        var writer: TakeWriter
        /// Held until the Take is finished and Repaired. Only the Drive has one.
        var access: DestinationAccess?
    }

    /// What `checkDestinations` found.
    enum Check: Equatable {
        case carryOn
        /// The last healthy Copy is about to fill: the caller should end the Take.
        case outOfSpace
    }

    /// What Repair needs once the Take has ended.
    struct Finished {
        var metadata: TakeMetadata
        var folders: [URL]
        var access: DestinationAccess?
        var statuses: [DestinationKind: CopyStatus]
    }

    /// The open Show, which gains a Drive folder when the Drive joins.
    private(set) var show: Show
    private(set) var metadata: TakeMetadata
    private(set) var copies: [CopyRecord] = []
    /// Called when any Copy's writer fails (on the main actor), so the owner can end the Take once none is left.
    var onCopyFailed: () -> Void = {}

    private let capture: Capture
    private let stems: [StemSpec]
    private let info: StemWriter.Info
    private let makeStem: (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink
    private let freeSpace: (URL) -> Int64

    /// Opens the Stems in each of `folders` (one per Copy, the Device first), writes `Take.json` there
    /// and starts capturing. `drive` is the access held for the Drive Copy, when there is one.
    init(
        show: Show, folders: [URL], drive: DestinationAccess?, metadata: TakeMetadata, stems: [StemSpec],
        info: StemWriter.Info, capture: Capture,
        makeStem: @escaping (URL, StemWriter.Info, _ resumingAt: UInt64?) throws -> any StemSink,
        freeSpace: @escaping (URL) -> Int64
    ) throws {
        self.show = show
        self.metadata = metadata
        self.stems = stems
        self.info = info
        self.capture = capture
        self.makeStem = makeStem
        self.freeSpace = freeSpace

        // One writer per Copy, each draining its own ring, so a slow Drive never holds up the Device.
        var records: [CopyRecord] = []
        for (index, folder) in folders.enumerated() {
            let kind = DestinationKind(index: index)
            let sinks = try stems.map { try makeStem(folder.appending(path: $0.file), info.described($0.description), nil) }
            try metadata.write(to: folder)
            records.append(CopyRecord(
                kind: kind, folder: folder, ring: capture.rings[index],
                writer: makeWriter(ring: capture.rings[index], kind: kind, stems: sinks),
                access: kind == .drive ? drive : nil))
        }
        for record in records { begin(record.writer, on: record.ring, joinFrame: 0) }
        copies = records
        capture.startCapturing(copies: records.count)
    }

    /// Places a Marker at the Take's current sample position (frames written so far), in every Stem
    /// of every Copy and in `Take.json`.
    @discardableResult
    func addMarker(named name: String? = nil) -> TakeMetadata.Marker {
        let marker = TakeMetadata.Marker(
            position: capture.takeFrameCount, name: name ?? "Marker \(metadata.markers.count + 1)", origin: .operator)
        metadata.markers.append(marker)
        // Take.json first: it's written whole and atomically, so a Marker survives even if the Stems'
        // next header commit never happens.
        writeMetadata()
        for copy in copies { copy.writer.setMarkers(stemMarkers) }
        return marker
    }

    /// How `kind`'s Copy is doing. A Copy that never started is missing.
    func status(_ kind: DestinationKind) -> CopyStatus {
        guard let copy = copies.first(where: { $0.kind == kind }) else { return .missing }
        return copy.writer.hasFailed ? .interrupted : .recording
    }

    /// Whether every Copy's writer has failed, so there is nowhere left to record.
    var allFailed: Bool { !copies.isEmpty && copies.allSatisfy { $0.writer.hasFailed } }

    /// Stretches written as silence in any Copy, as `Take.json` records them.
    /// With `takeEnd`, a Copy that is still interrupted is missing everything from where it stopped to there.
    func gaps(takeEnd: Int? = nil) -> [TakeMetadata.Gap] {
        var gaps: [TakeMetadata.Gap] = []
        for copy in copies {
            for range in copy.writer.gaps {
                gaps.append(.init(copy: copy.kind, start: range.lowerBound, end: range.upperBound))
            }
            if let takeEnd, copy.writer.hasFailed, copy.writer.framesWritten < takeEnd {
                gaps.append(.init(copy: copy.kind, start: copy.writer.framesWritten, end: takeEnd))
            }
        }
        return gaps.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// Looks for a Destination that has become available since the Take started. A Drive that appears
    /// joins the running Take: its Stems start with silence up to the join point, which is recorded as
    /// a Gap in `Take.json` on both Copies. A Drive Copy that failed rejoins the same way when its
    /// Destination comes back. A Copy that is low on space retires; when the last healthy one is, this
    /// returns `.outOfSpace` and leaves the Take running for the caller to finish.
    ///
    /// `drive` is asked only when a Drive could join or rejoin, and each access it returns is either
    /// kept for the Take or released here.
    func checkDestinations(drive: () -> DestinationAccess?) -> Check {
        // Keep 60 s of audio free on each Destination. A Copy that's short stops cleanly while another
        // has room; when the last healthy one is short the Take finalizes, before anything fills.
        let reserve = SpaceReserve(channelCount: metadata.usbChannels.count, sampleRate: info.sampleRate)
        let healthy = copies.filter { !$0.writer.hasFailed }
        let low = healthy.filter { reserve.isLow(free: freeSpace($0.folder)) }
        if !low.isEmpty {
            if low.count == healthy.count { return .outOfSpace }
            for copy in low {
                capture.disable(copy: copy.kind.index)
                copy.writer.retire()
            }
        }
        if copies.count == 1, let access = drive() {
            attachDrive(access, replacing: nil, reserve: reserve)
        }
        if copies.count == 2, copies[1].writer.isFinished, copies[1].writer.hasFailed, let access = drive() {
            attachDrive(access, replacing: copies[1], reserve: reserve)
        }
        persistGaps()
        return .carryOn
    }

    /// Stops capturing, waits until every Stem is written and finalized and records the Gaps.
    /// A Copy that failed during the Take doesn't make this throw; see `Finished.statuses`.
    func finish() -> Finished {
        capture.stopCapturing()
        var statuses = Dictionary(uniqueKeysWithValues: DestinationKind.allCases.map { ($0, status($0)) })
        for copy in copies { copy.writer.stop() }
        persistGaps(takeEnd: capture.takeFrameCount)
        for copy in copies where statuses[copy.kind] == .recording && copy.writer.hasFailed {
            // A Copy can fail while its writer drains at stop.
            statuses[copy.kind] = .interrupted
        }
        return Finished(metadata: metadata, folders: copies.map(\.folder), access: copies.lazy.compactMap(\.access).first, statuses: statuses)
    }

    // MARK: - Drive join and rejoin

    /// Starts the Drive Copy, or restarts it over `old`. Both start new Stems in a Take folder under
    /// `access` and bring the Copy in through the same handshake; they differ in where the folder
    /// comes from, whether the Stems resume `old`'s and what happens to `old`'s access.
    private func attachDrive(_ access: DestinationAccess, replacing old: CopyRecord?, reserve: SpaceReserve) {
        var show = show
        do {
            let folder: URL
            if old == nil {
                guard !reserve.isLow(free: freeSpace(access.folder)) else { access.release(); return }
                folder = try show.joinDrive(access.folder)
            } else {
                // The Drive may have come back at a different path (a remount), so find the Take folder
                // under the folder we were just given.
                folder = access.folder
                    .appending(path: show.name, directoryHint: .isDirectory)
                    .appending(path: String(format: "Take %02d", show.takeCount), directoryHint: .isDirectory)
                guard FileManager.default.fileExists(atPath: folder.path), !reserve.isLow(free: freeSpace(folder)) else {
                    access.release()
                    return
                }
                try show.useDrive(access.folder)
            }
            let counts = old?.writer.stemFrameCounts
            let sinks = try stems.enumerated().map { index, spec in
                try makeStem(folder.appending(path: spec.file), info.described(spec.description), counts?[index])
            }
            // A Take folder that was rejoined already has its Take.json.
            if old == nil { try metadata.write(to: folder) }

            let ring = capture.rings[DestinationKind.drive.index]
            let writer = makeWriter(ring: ring, kind: .drive, stems: sinks, priorGaps: old?.writer.gaps ?? [])
            begin(writer, on: ring, joinFrame: -1)
            if !metadata.markers.isEmpty { writer.setMarkers(stemMarkers) }
            capture.requestJoin(copy: DestinationKind.drive.index)

            let record = CopyRecord(kind: .drive, folder: folder, ring: ring, writer: writer, access: access)
            if old == nil { copies.append(record) } else { copies[1] = record }
            old?.access?.release()
            self.show = show
        } catch {
            access.release()
        }
    }

    // MARK: - Helpers

    private func makeWriter(ring: SampleRing, kind: DestinationKind, stems sinks: [any StemSink], priorGaps: [Range<Int>] = []) -> TakeWriter {
        TakeWriter(ring: ring, stems: sinks, commitInterval: info.sampleRate * 2, onFailure: { [weak self, capture] in
            capture.disable(copy: kind.index)
            Task { @MainActor in self?.onCopyFailed() }
        }, priorGaps: priorGaps)
    }

    /// Empties `ring`, says which Take frame its Copy starts at (-1 until the real-time thread picks
    /// one for a Copy that joins mid-Take) and starts its writer.
    private func begin(_ writer: TakeWriter, on ring: SampleRing, joinFrame: Int) {
        ring.discardAll()
        ring.joinFrame.store(joinFrame, ordering: .releasing)
        writer.start()
    }

    private var stemMarkers: [StemMarker] {
        metadata.markers.map { StemMarker(position: UInt32(clamping: $0.position), label: $0.name) }
    }

    private func writeMetadata() {
        for copy in copies { try? metadata.write(to: copy.folder) }
    }

    /// Writes the Gaps found so far into `Take.json` in every Copy.
    private func persistGaps(takeEnd: Int? = nil) {
        let gaps = gaps(takeEnd: takeEnd)
        guard gaps != metadata.gaps else { return }
        metadata.gaps = gaps
        writeMetadata()
    }
}

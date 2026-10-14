import Foundation
import TakeFile

/// Drive only (#196, ADR 0006, #630): what the screen says about moving Drive only Takes to the Drive: a line while
/// they move, then one counting what came of the latest move, and each Take with why one stays on this iPhone.
public struct MoveReport: Equatable, Sendable {
    /// One Take a move took up or left where it is.
    public struct Entry: Equatable, Sendable, Identifiable {
        public enum Status: Equatable, Sendable {
            case moved
            /// Still on this iPhone: a check failed, or the move left it where it is.
            case kept
            /// A Take started before this one was done; it moves after Stop.
            case paused
        }

        public var show: String
        public var take: Int
        public var status: Status
        /// Why a kept Take stays on this iPhone, in the move's words.
        public var reasons: [String]
        fileprivate var deviceWord: String

        public var id: String { "\(show)/\(take)" }
        /// "2026-10-06 Show, Take 01".
        public var title: String { "\(show), \(TakeMetadata.name(take: take))" }
        public var statusText: String {
            switch status {
            case .moved: "Moved to the Drive."
            case .kept: "Kept on this \(deviceWord)."
            case .paused: "Paused for a Take; it moves after Stop."
            }
        }
    }

    public var isMoving: Bool
    public var entries: [Entry]
    private var deviceWord: String

    public var moved: Int { entries.filter { $0.status == .moved }.count }
    public var kept: Int { entries.filter { $0.status == .kept }.count }
    public var paused: Int { entries.filter { $0.status == .paused }.count }

    /// The line on the record screen, or nil when there is nothing to say.
    public var line: String? {
        if isMoving { return "Moving Takes to the Drive…" }
        var parts: [String] = []
        func count(_ n: Int, _ words: String) {
            guard n > 0 else { return }
            // The first count names the Takes; the next ones only count.
            parts.append(parts.isEmpty ? "\(n) \(n == 1 ? "Take" : "Takes") \(words)." : "\(n) \(words).")
        }
        count(moved, "moved to the Drive")
        count(kept, "kept on this \(deviceWord)")
        if paused > 0 { parts.append("Paused for the Take; the rest move after Stop.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The record screen's alert for it, or nil: only where moving is offered (`Recorder.movesDriveOnlyTakes`) and no
    /// Take runs. Once a move has Takes to list, its button opens them (`showMoves`).
    public func alert(isOffered: Bool, isRecording: Bool) -> ScreenAlert? {
        guard isOffered, !isRecording, let line else { return nil }
        let tone: ScreenAlert.Tone = isMoving ? .info : isProblem ? .warning : .ok
        return ScreenAlert(id: "moves", priority: .copyResult, tone: tone, text: line, action: isMoving || entries.isEmpty ? nil : .showMoves)
    }

    /// Whether a Take stays on this iPhone.
    public var isProblem: Bool { kept > 0 }

    /// - Parameters:
    ///   - moves: what came of each Take the latest move took up; a Take already gone from this iPhone isn't listed.
    ///   - skips: the Takes it found and left where they are.
    ///   - deviceWord: the device the app runs on (iPhone, iPad or Mac).
    init(isMoving: Bool, moves: [StandInMove.Result], skips: [TakeMover.Movable], deviceWord: String = "iPhone") {
        self.isMoving = isMoving
        self.deviceWord = deviceWord
        var entries: [Entry] = []
        for move in moves {
            let entry: (Entry.Status, [String])? = switch move.outcome {
            case .moved: (.moved, [])
            case .kept(let reasons): (.kept, reasons)
            case .stopped: (.paused, [])
            case .gone: nil
            }
            if let (status, reasons) = entry {
                entries.append(.init(show: move.show, take: move.take, status: status, reasons: reasons, deviceWord: deviceWord))
            }
        }
        for skip in skips {
            guard case .skipped(let reason) = skip.kind else { continue }
            entries.append(.init(
                show: skip.show, take: skip.take, status: .kept, reasons: [Self.words(reason, take: skip.take, deviceWord: deviceWord)],
                deviceWord: deviceWord))
        }
        self.entries = entries.sorted { ($0.show, $0.take) < ($1.show, $1.take) }
    }

    /// Why the move left a Take where it is, in plain words.
    static func words(_ reason: TakeMover.Movable.SkipReason, take: Int, deviceWord: String) -> String {
        switch reason {
        case .anotherRecording: "The Drive has a different \(TakeMetadata.name(take: take)) in this Show."
        case .driveHasGaps: "The Drive copy has Gaps that Repair couldn't fill."
        // A kept stand-in may hold the only copy of what its Drive missed.
        case .noDriveTake:
            "This Drive doesn't have this Take. Connect the Drive it was recorded to. This \(deviceWord) holds the part that Drive missed, so keep it."
        case .unreadable: "The Drive copy of this Take can't be read."
        }
    }
}

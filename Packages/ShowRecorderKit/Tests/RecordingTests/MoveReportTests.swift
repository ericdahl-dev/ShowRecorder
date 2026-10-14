import Foundation
@testable import Recording
import Testing

/// Drive only (#630): the words the screen uses for moving Takes to the Drive.
@Suite("Move report")
struct MoveReportTests {
    let show = "2026-10-06 Show"
    func result(_ take: Int, _ outcome: StandInMove.Outcome) -> StandInMove.Result { .init(show: show, take: take, outcome: outcome) }
    func skip(_ take: Int, _ reason: TakeMover.Movable.SkipReason) -> TakeMover.Movable {
        .init(show: show, take: take, deviceFolder: URL(filePath: "/x"), kind: .skipped(reason))
    }

    @Test("While moving, the line says so")
    func moving() {
        let report = MoveReport(isMoving: true, moves: [], skips: [])
        #expect(report.line == "Moving Takes to the Drive…")
        #expect(!report.isProblem)
    }

    @Test("Takes all moved: one count, not a problem")
    func allMoved() {
        let report = MoveReport(isMoving: false, moves: [result(1, .moved), result(2, .moved)], skips: [])
        #expect(report.line == "2 Takes moved to the Drive.")
        #expect(report.moved == 2)
        #expect(!report.isProblem)
        #expect(report.entries.map(\.statusText) == ["Moved to the Drive.", "Moved to the Drive."])
    }

    @Test("A Take kept or left where it is counts as kept on this iPhone, with why, and is a problem")
    func keptAndSkipped() {
        let report = MoveReport(
            isMoving: false, moves: [result(1, .moved), result(2, .kept(["Take 02, channel 1 has different audio on the Drive."]))],
            skips: [skip(3, .anotherRecording)])
        #expect(report.line == "1 Take moved to the Drive. 2 kept on this iPhone.")
        #expect(report.kept == 2)
        #expect(report.isProblem)
        #expect(report.entries.map(\.title) == ["2026-10-06 Show, Take 01", "2026-10-06 Show, Take 02", "2026-10-06 Show, Take 03"])
        #expect(report.entries[1].statusText == "Kept on this iPhone.")
        #expect(report.entries[1].reasons == ["Take 02, channel 1 has different audio on the Drive."])
        #expect(report.entries[2].reasons == ["The Drive has a different Take 03 in this Show."])
    }

    @Test("Only kept Takes name the Take in the first count")
    func onlyKept() {
        let report = MoveReport(isMoving: false, moves: [result(1, .kept(["x"]))], skips: [], deviceWord: "Mac")
        #expect(report.line == "1 Take kept on this Mac.")
    }

    @Test("Each reason a Take is left where it is, in plain words")
    func skipReasons() {
        let report = MoveReport(isMoving: false, moves: [], skips: [skip(1, .driveHasGaps), skip(2, .noDriveTake), skip(3, .unreadable)])
        #expect(report.entries.map(\.reasons) == [
            ["The Drive copy has Gaps that Repair couldn't fill."],
            ["This Drive doesn't have this Take. Connect the Drive it was recorded to. This iPhone holds the part that Drive missed, so keep it."],
            ["The Drive copy of this Take can't be read."],
        ])
    }

    @Test("A move stopped by a Take says it resumes after Stop, and doesn't count as kept")
    func paused() {
        let report = MoveReport(isMoving: false, moves: [result(1, .moved), result(2, .stopped)], skips: [])
        #expect(report.line == "1 Take moved to the Drive. Paused for the Take; the rest move after Stop.")
        #expect(report.kept == 0)
        #expect(report.entries.last?.statusText == "Paused for a Take; it moves after Stop.")
    }

    @Test("A Take already gone from this iPhone isn't listed or counted")
    func gone() {
        let report = MoveReport(isMoving: false, moves: [result(1, .gone)], skips: [])
        #expect(report.entries.isEmpty)
        #expect(report.line == nil)
    }

    @Test("The screen's alert: only where moving is offered and no Take runs; Details only once there are Takes to list")
    func alert() {
        let moving = MoveReport(isMoving: true, moves: [], skips: [])
        #expect(moving.alert(isOffered: true, isRecording: false) == ScreenAlert(id: "moves", priority: .copyResult, tone: .info, text: "Moving Takes to the Drive…"))
        #expect(moving.alert(isOffered: false, isRecording: false) == nil, "not offered: nothing shows")
        #expect(moving.alert(isOffered: true, isRecording: true) == nil, "never during a Take")

        let moved = MoveReport(isMoving: false, moves: [result(1, .moved)], skips: [])
        #expect(moved.alert(isOffered: true, isRecording: false)
            == ScreenAlert(id: "moves", priority: .copyResult, tone: .ok, text: "1 Take moved to the Drive.", action: .showMoves))

        let kept = MoveReport(isMoving: false, moves: [result(1, .kept(["x"]))], skips: [])
        #expect(kept.alert(isOffered: true, isRecording: false)?.tone == .warning)

        #expect(MoveReport(isMoving: false, moves: [], skips: []).alert(isOffered: true, isRecording: false) == nil, "nothing to say")
    }
}

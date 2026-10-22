import Foundation
import Testing
@testable import WatchRemote

/// The iPhone's side of the watch remote (#100): each command from the wrist runs once, fresh, through the same
/// actions as the record screen's own buttons.
@MainActor
@Suite("Watch command desk")
struct WatchCommandDeskTests {
    /// A recorder in memory: Armed or recording, and what the watch asked of it.
    final class Recorder {
        var isRecording = false
        var refusal: String?
        var markerRefusal: String?
        var starts = 0, stops = 0, markers = 0
    }

    static let t0 = Date(timeIntervalSince1970: 1_000_000)

    static func desk(_ recorder: Recorder, now: @escaping () -> Date = { t0 }) -> WatchCommandDesk {
        WatchCommandDesk(now: now, actions: .init(
            start: {
                if let refusal = recorder.refusal { return refusal }
                recorder.starts += 1
                recorder.isRecording = true
                return nil
            },
            stop: {
                guard recorder.isRecording else { return false }
                recorder.stops += 1
                recorder.isRecording = false
                return true
            },
            marker: {
                guard recorder.isRecording else { return WatchCommandDesk.notRecording }
                if let refusal = recorder.markerRefusal { return refusal }
                recorder.markers += 1
                return nil
            }))
    }

    static func command(_ kind: WatchCommand.Kind, at time: Date = t0) -> WatchCommand {
        WatchCommand(id: UUID(), kind: kind, sentAt: time)
    }

    @Test("A Marker the recorder didn't place is refused with why, not confirmed (#882)")
    func markerNotPlaced() {
        let recorder = Recorder()
        recorder.isRecording = true
        recorder.markerRefusal = "3 per Take on Free"
        #expect(Self.desk(recorder).handle(Self.command(.marker)) == .refused("3 per Take on Free"))
        #expect(recorder.markers == 0)
    }

    @Test("Start, Marker and Stop run the recorder's own actions and say they're done")
    func runs() {
        let recorder = Recorder()
        let desk = Self.desk(recorder)

        #expect(desk.handle(Self.command(.start)) == .done)
        #expect(desk.handle(Self.command(.marker)) == .done)
        #expect(desk.handle(Self.command(.stop)) == .done)
        #expect((recorder.starts, recorder.markers, recorder.stops) == (1, 1, 1))
    }

    @Test("A command the link delivers twice runs once, and the second gets the same answer")
    func once() {
        let recorder = Recorder()
        recorder.isRecording = true
        let desk = Self.desk(recorder)
        let marker = Self.command(.marker)

        #expect(desk.handle(marker) == .done)
        #expect(desk.handle(marker) == .done)
        #expect(recorder.markers == 1)
        #expect(desk.handle(Self.command(.marker)) == .done, "a second tap is a second Marker")
        #expect(recorder.markers == 2)
    }

    @Test("A Start or Stop that arrives late (the link came back) is dropped, never replayed")
    func late() {
        let recorder = Recorder()
        recorder.isRecording = true
        var now = Self.t0
        let desk = Self.desk(recorder, now: { now })
        now = Self.t0.addingTimeInterval(WatchCommandDesk.maxAge + 1)

        #expect(desk.handle(Self.command(.stop)) == .tooLate)
        #expect(desk.handle(Self.command(.start)) == .tooLate)
        #expect(recorder.isRecording, "the Take carries on")
        #expect(recorder.stops == 0)
    }

    @Test("A Start the recorder refuses (a limit, no Drive) says why")
    func refused() {
        let recorder = Recorder()
        recorder.refusal = "Choose where Takes go in Settings"
        #expect(Self.desk(recorder).handle(Self.command(.start)) == .refused("Choose where Takes go in Settings"))
    }

    @Test("A Marker or Stop with no Take running is refused, and nothing happens")
    func notRecording() {
        let recorder = Recorder()
        let desk = Self.desk(recorder)
        #expect(desk.handle(Self.command(.marker)) == .refused(WatchCommandDesk.notRecording))
        #expect(desk.handle(Self.command(.stop)) == .refused(WatchCommandDesk.notRecording))
        #expect((recorder.markers, recorder.stops) == (0, 0))
    }
    @Test("A command from the future (a watch clock ahead, or a resend stamped wrong) is dropped too")
    func future() {
        let recorder = Recorder()
        recorder.isRecording = true
        let desk = Self.desk(recorder)
        #expect(desk.handle(Self.command(.stop, at: Self.t0.addingTimeInterval(WatchCommandDesk.maxAge + 1))) == .tooLate)
        #expect(recorder.isRecording)
    }
}

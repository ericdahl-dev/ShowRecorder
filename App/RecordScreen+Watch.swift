import Recording
import TakeActivity
import WatchRemote

/// The Apple Watch remote (#100), as the record screen sees it: what the watch shows, from what the screen already
/// shows, and the watch's three commands, through the same paths as the screen's own buttons.
extension RecordScreenModel {
    var watchStatus: WatchStatus { screen.watchStatus(snapshot) }

    /// The same problems for the recording Live Activity (#545), which alerts when one is new.
    var liveActivityProblems: [TakeActivityProblem] {
        watchStatus.problems.map { TakeActivityProblem(id: $0.rawValue, text: $0.text, symbol: $0.symbol) }
    }

    var watchActions: WatchCommandDesk.Actions {
        WatchCommandDesk.Actions(
            start: { [weak self] in
                guard let self else { return WatchRemoteModel.openPhoneText }
                // The iPhone can't open the mic from the background: Start works only once it's Armed.
                guard recorder.isArmed else { return WatchRemoteModel.openPhoneText }
                guard !recorder.isRecording, !recorder.isStarting, !startRequested else { return nil }
                // The last Take's Stop was accepted but its Stems are still being written (#652).
                guard !recorder.isFinishing else { return RecorderError.finishing.errorDescription }
                guard !speedTest.isRunning else { return "A Drive speed test is running." }
                // The Record button's own path: the tier, the Trial and the Destinations are judged here.
                record()
                // The Take is starting off the main thread (#914): the watch hears of it when it runs; a start that then fails shows on the
                // phone (`recordError`).
                return recorder.isRecording || recorder.isStarting || startRequested ? nil : (recordError ?? recordBlock?.text ?? "Couldn't start recording")
            },
            stop: { [weak self] in
                guard let self, recorder.isRecording || recorder.isStarting || startRequested else { return false }
                // The reply is "stopped", as before; the Stop itself finishes after it.
                Task { await stop() }
                return true
            },
            marker: { [weak self] in
                guard let self, recorder.isRecording else { return WatchCommandDesk.notRecording }
                // Past the Free limit nothing is placed, and the watch says why instead of confirming it (#882).
                return sequencer.addMarker() ? nil : "\(Entitlement.freeMarkerLimit) per Take on Free"
            })
    }
}

import Recording
import TakeActivity
import WatchRemote

/// The Apple Watch remote (#100), as the record screen sees it: what the watch shows, from what the screen already
/// shows, and the watch's three commands, through the same paths as the screen's own buttons.
extension RecordScreenModel {
    var watchStatus: WatchStatus {
        let take = recorder.isRecording ? takeStartedAt.map {
            WatchStatusMaker.Take(startedAt: $0, title: takeTitle, markerCount: recorder.takeMarkers.count)
        } : nil
        let mixerDown = if case .down = mixer.status { true } else { false }
        let driveAvailable = if case .available = drive.status { true } else { false }
        return WatchStatusMaker.make(
            isArmed: recorder.isArmed, take: take, chips: chips, driveAvailable: driveAvailable,
            copies: copies,
            dropoutCount: recorder.isRecording ? recorder.dropoutCount : 0, mixerDown: mixerDown)
    }

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
                guard !recorder.isRecording else { return nil }
                // The last Take's Stop was accepted but its Stems are still being written (#652).
                guard !recorder.isFinishing else { return RecorderError.finishing.errorDescription }
                guard !speedTest.isRunning else { return "A Drive speed test is running." }
                // The Record button's own path: the tier, the Trial and the Destinations are judged here.
                record()
                return recorder.isRecording ? nil : (recordError ?? recordBlock?.text ?? "Couldn't start recording")
            },
            stop: { [weak self] in
                guard let self, recorder.isRecording else { return false }
                // The reply is "stopped", as before; the Stop itself finishes after it.
                Task { await stop() }
                return true
            },
            marker: { [weak self] in
                guard let self, recorder.isRecording else { return false }
                sequencer.addMarker()
                return true
            })
    }
}

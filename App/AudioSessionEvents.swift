import Foundation
import OSLog
import Recording
#if os(iOS)
import AVFAudio
#endif

/// Keeps a Take going through screen locks, backgrounding and audio session interruptions.
///
/// `InterruptionPolicy` decides; this carries its decisions out on the recorder and logs them.
extension RecordScreenModel {
    static let sessionLog = Logger(subsystem: "dev.ericdahl.ShowRecorder", category: "AudioSession")

    /// Feeds one event to the policy and carries out what it decides.
    func handle(_ event: InterruptionPolicy.Event) {
        let response = interruptions.handle(event, isRecording: recorder.isRecording)
        if let line = response.log { Self.sessionLog.notice("\(line, privacy: .public)") }
        switch response.action {
        case .none:
            break
        case .restartInput:
            do {
                try recorder.restartInput()
                handle(.restarted)
            } catch {
                handle(.restartFailed(String(describing: error)))
            }
        case .replaceDevice:
            guard let choice = devices.first(where: { $0.id == selectedDeviceID }) else {
                handle(.restartFailed("no input is selected"))
                return
            }
            do {
                let wasRecording = recorder.isRecording
                let continued = try recorder.restartInput(on: choice.make())
                handle(wasRecording && !continued ? .takeEndedByReset : .restarted)
            } catch {
                handle(.restartFailed(String(describing: error)))
            }
        }
    }

    #if os(iOS)
    /// Turns audio session interruptions and media services resets into policy events.
    func watchAudioSession() async {
        let resets = Task { await watchMediaServicesResets() }
        defer { resets.cancel() }
        let interruptions = NotificationCenter.default
            .notifications(named: AVAudioSession.interruptionNotification)
            .compactMap { Self.interruptionEvent(from: $0.userInfo) }
        for await event in interruptions { handle(event) }
    }

    private func watchMediaServicesResets() async {
        let resets = NotificationCenter.default
            .notifications(named: AVAudioSession.mediaServicesWereResetNotification)
            .map { _ in () }
        for await _ in resets { handle(.mediaServicesReset) }
    }

    nonisolated private static func interruptionEvent(from info: [AnyHashable: Any]?) -> InterruptionPolicy.Event? {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return nil }
        switch type {
        case .began:
            return .interruptionBegan
        case .ended:
            let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            return .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
    #endif
}

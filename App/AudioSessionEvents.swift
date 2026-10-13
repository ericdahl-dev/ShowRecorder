import Foundation
import OSLog
import Recording
#if os(iOS)
import AVFAudio
#endif

/// Keeps a Take going through screen locks, backgrounding and audio session interruptions.
///
/// `InterruptionPolicy` decides and the `TakeSequencer` carries it out; this turns the system's notifications into events.
extension RecordScreenModel {
    static let sessionLog = Logger(subsystem: "dev.ericdahl.ShowRecorder", category: "AudioSession")

    /// Feeds one event to the policy; the `TakeSequencer` carries out what it decides.
    func handle(_ event: InterruptionPolicy.Event) {
        sequencer.handle(event)
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

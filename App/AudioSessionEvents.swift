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
    func handle(_ event: InterruptionPolicy.Event) async {
        await sequencer.handle(event)
    }

    #if os(iOS)
    /// Turns audio session interruptions and media services resets into policy events.
    func watchAudioSession() async {
        let resets = Task { await watchMediaServicesResets() }
        defer { resets.cancel() }
        let interruptions = NotificationCenter.default
            .notifications(named: AVAudioSession.interruptionNotification)
            .compactMap { Self.interruptionEvent(from: $0.userInfo) }
        for await event in interruptions { await handle(event) }
    }

    private func watchMediaServicesResets() async {
        let resets = NotificationCenter.default
            .notifications(named: AVAudioSession.mediaServicesWereResetNotification)
            .map { _ in () }
        for await _ in resets { await handle(.mediaServicesReset) }
    }

    nonisolated private static func interruptionEvent(from info: [AnyHashable: Any]?) -> InterruptionPolicy.Event? {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return nil }
        switch type {
        case .began:
            // The reason key is deprecated in the iOS 27 SDK. Its replacement,
            // AVAudioSessionDeactivationContext.interruptionDetails.reason, isn't adopted yet because it
            // can't be tried without an iOS 27 device. The deployment target is iOS 26, so no #available
            // is needed. A missing key falls back to the general wording.
            return .interruptionBegan(reason: .init(sessionReason: info?[AVAudioSessionInterruptionReasonKey] as? UInt))
        case .ended:
            let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            return .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
    #endif
}

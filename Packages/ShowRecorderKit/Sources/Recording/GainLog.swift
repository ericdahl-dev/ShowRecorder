import AutoGain
import Foundation
import MixerLink
import TakeFile

/// How gain on the Mixer is written down (#450, #554): a gain step as the gain log records it, the Marker placed with
/// it during a Take, and the names the log and the auto-gain sheet give Mix Hold's settings.
enum GainLog {
    /// A gain step as the log records it: the gain and every compensated setting from and to (reversed for an undo).
    static func change(_ step: GainStep, usbChannel: Int, reason: TakeMetadata.GainChange.Reason, undoing: Bool = false) -> TakeMetadata.GainChange {
        let compensations = step.changes.map { change in
            let held = step.held[change.setting] ?? change.toDb
            return TakeMetadata.GainChange.Compensation(
                channel: change.setting.channel, setting: change.setting.parameter.logName,
                fromDb: undoing ? held : change.fromDb, toDb: undoing ? change.fromDb : held)
        }
        return TakeMetadata.GainChange(
            usbChannel: usbChannel, channel: step.channel, headamp: step.headamp,
            fromGainDb: undoing ? step.toGainDb : step.fromGainDb, toGainDb: undoing ? step.fromGainDb : step.toGainDb,
            reason: reason, compensations: compensations)
    }

    /// The Marker placed where the gain changed: "Kick: gain +3.0 dB (auto-gain)".
    static func markerName(for change: TakeMetadata.GainChange, channelName: String) -> String {
        String(format: "%@: gain %+.1f dB (%@)", channelName, change.toGainDb - change.fromGainDb, change.reason.word)
    }
}

extension MixHold.Limit {
    /// The setting that stopped Mix Hold and its end stop, as the auto-gain sheet says it: "Channel 1's gate threshold
    /// is at its end stop (0 dB)".
    public var explanation: String {
        let db = endDb > 0 ? String(format: "+%g", endDb) : String(format: "%g", endDb)
        return "Channel \(setting.channel)'s \(setting.parameter.logName) is at its end stop (\(db) dB)"
    }
}

extension MixHold.Parameter {
    /// "gate threshold", "fader", "send 3", as the gain log names it.
    var logName: String {
        switch self {
        case .gateThreshold: "gate threshold"
        case .compressorThreshold: "compressor threshold"
        case .mainFader: "fader"
        case .otherMain(let main): main == 1 ? "mono" : "main \(main)"
        case .send(let bus): "send \(bus)"
        }
    }
}

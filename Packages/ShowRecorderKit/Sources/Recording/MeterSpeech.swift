/// What VoiceOver says for one meter (#249). Coarse on purpose: the zone, and whether the channel is near or past
/// clipping. A dB number would change on every frame and is no use heard aloud.
public enum MeterSpeech {
    public static func spoken(zone: MeterZone, silent: Bool, peakIsHot: Bool, clipped: Bool) -> String {
        let level: String = if silent { "Silent" } else {
            switch zone {
            case .low: "Below the target"
            case .onTarget: "On target"
            case .hot: "Above the target"
            }
        }
        let parts = (clipped ? ["Clipped"] : []) + (peakIsHot ? ["Near clipping"] : []) + [level]
        return parts.joined(separator: ". ")
    }
}

extension ChannelMeter {
    /// What VoiceOver says for this meter; see `MeterSpeech`.
    public func spoken(clipped: Bool) -> String {
        MeterSpeech.spoken(zone: zone, silent: averageDbfs <= VUMeter.floorDbfs, peakIsHot: peakIsHot, clipped: clipped)
    }
}

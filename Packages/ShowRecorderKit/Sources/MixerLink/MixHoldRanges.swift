import AutoGain

extension MixHoldDesk {
    /// How far Mix Hold may move each compensated setting: the ends of the scale the Mixer driver writes it with (#442), so the
    /// limits and the values written can't disagree. A level at the bottom of the fader's scale is off.
    static var mixHoldRanges: MixHold.Ranges {
        let fader = scale(of: .mainFader).dbRange
        return MixHold.Ranges(fader: fader, send: scale(of: .send(1)).dbRange,
                             gateThreshold: scale(of: .gateThreshold).dbRange,
                             compressorThreshold: scale(of: .compressorThreshold).dbRange, offDb: fader.lowerBound)
    }
}

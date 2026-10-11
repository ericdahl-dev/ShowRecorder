import MixerLink

extension TakeMetadata.USBChannel {
    init(usbChannel: Int, stemFile: String, source: Source) {
        self.init(
            usbChannel: usbChannel,
            stemFile: stemFile,
            name: source.name,
            hasMixerName: source.hasMixerName,
            color: Color(hue: source.color.hue.name, inverted: source.color.inverted),
            muted: source.isMuted,
            fader: source.fader,
            inputSource: source.inputSource)
    }
}

import MixerLink

/// A real reason to believe some USB Channels won't be recorded. There is no expected channel
/// count: a device is only short when the system granted fewer channels than the input offers, or
/// when the Mixer Link identified a Mixer that sends more USB Channels than the device delivers.
public struct USBChannelShortfall: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The input offers `offered` channels, but the system granted fewer (iOS can).
        case systemGrantedFewer(offered: Int)
        /// The identified `mixer` sends `mixerSends` USB Channels.
        case mixerSendsMore(mixer: MixerIdentity, mixerSends: Int)
    }

    /// USB Channels the Armed device actually sends.
    public var usbChannelCount: Int
    public var reason: Reason

    public init(usbChannelCount: Int, reason: Reason) {
        self.usbChannelCount = usbChannelCount
        self.reason = reason
    }

    /// - Parameters:
    ///   - usbChannelCount: USB Channels the Armed device sends; 0 when nothing is Armed.
    ///   - offeredChannelCount: the most input channels the route offers, where the system reports
    ///     it (iOS); nil elsewhere.
    ///   - mixer: the Mixer the Mixer Link identified, if it is up.
    ///   - capabilities: what that Mixer's driver knows about the model.
    /// - Returns: nil when there is nothing to warn about, so the count is just shown.
    public static func check(
        usbChannelCount: Int, offeredChannelCount: Int?,
        mixer: MixerIdentity?, capabilities: MixerCapabilities?
    ) -> USBChannelShortfall? {
        guard usbChannelCount > 0 else { return nil }
        if let offered = offeredChannelCount, offered > usbChannelCount {
            return USBChannelShortfall(usbChannelCount: usbChannelCount, reason: .systemGrantedFewer(offered: offered))
        }
        if let mixer, let mixerSends = capabilities?.usbChannelCount, mixerSends > usbChannelCount {
            return USBChannelShortfall(usbChannelCount: usbChannelCount, reason: .mixerSendsMore(mixer: mixer, mixerSends: mixerSends))
        }
        return nil
    }

    /// The banner text. It names a Mixer only when one was identified.
    public var message: String {
        let sent = usbChannelCount == 1 ? "1 USB Channel" : "\(usbChannelCount) USB Channels"
        switch reason {
        case .systemGrantedFewer(let offered):
            return "This input offers \(offered) channels, but the system is sending the recorder \(sent), so some channels won't be recorded."
        case .mixerSendsMore(let mixer, let mixerSends):
            return "This device sends \(sent). The \(mixer.model) (\(mixer.networkName)) sends \(mixerSends), so some of the Mixer won't be recorded."
        }
    }
}

/// The item in a meter lane's menu that arms or stops arming its USB Channel (#991).
///
/// Built from steady data only, the channel number and whether it is armed, never the level, so a lane's menu is the
/// same value from one meter reading to the next and the lane need not be rebuilt under an open menu (#1135).
public struct ChannelArmMenuItem: Equatable, Sendable {
    /// The USB Channel, from 1.
    public let channel: Int
    /// Whether the channel is armed now.
    public let isArmed: Bool

    /// `notArmed`: the USB Channels (from 1) drawn as not armed.
    public init(channel: Int, notArmed: Set<Int>) {
        self.channel = channel
        isArmed = !notArmed.contains(channel)
    }

    public var title: String { "\(accessibilityName) \(channel)" }

    public var systemImage: String { isArmed ? "circle.slash" : "circle" }

    /// The VoiceOver action's name.
    public var accessibilityName: String { isArmed ? "Don't arm channel" : "Arm channel" }

    /// What a tap asks for: true arms the channel, false stops arming it.
    public var armsOnTap: Bool { !isArmed }
}

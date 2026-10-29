import Foundation

/// Where choosing which USB Channels are armed (recorded) is offered: Debug builds only, until Eric has tried it on a
/// device (#991, CLAUDE.md). Opening it up is this one rule.
public enum ChannelArmingAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugOnly

    /// `environment` is nil until StoreKit has answered.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

/// The USB Channels the operator chose not to arm on an Audio interface (#991): they get no Stem. Every channel
/// is armed until this says otherwise, so a new interface, or a channel count that grows, needs no migration. Kept per
/// Audio interface, by its name, like the saved channel names.
public enum ChannelArming {
    private static let key = "notArmedChannels"

    /// The channels (from 1) not armed on `interface`; none when nothing was saved.
    public static func notArmed(on interface: String, from defaults: UserDefaults = .standard) -> Set<Int> {
        Set(all(from: defaults)[interface] ?? [])
    }

    static func save(_ channels: Set<Int>, on interface: String, to defaults: UserDefaults) {
        var saved = all(from: defaults)
        saved[interface] = channels.isEmpty ? nil : channels.sorted()
        defaults.set(saved, forKey: key)
    }

    private static func all(from defaults: UserDefaults) -> [String: [Int]] {
        defaults.dictionary(forKey: key) as? [String: [Int]] ?? [:]
    }

    /// Whether record is off for lack of an armed channel: a press would record nothing. Never while a Take runs or starts: the
    /// button is Stop then, and the running Take has its own channels.
    public static func nothingToRecord(recordedChannelCount: Int, usbChannelCount: Int, isRecording: Bool, isStarting: Bool) -> Bool {
        usbChannelCount > 0 && recordedChannelCount == 0 && !isRecording && !isStarting
    }

    /// The USB Channels (from 1) a lane shows as not armed right now: during a Take, the ones it was started without; between
    /// Takes, the ones a Take pressed now would leave out, so Free and an unknown tier show none.
    public static func notArmedLanes(
        chosen: Set<Int>, license: License, channelCount: Int, takeAllowance: TakeAllowance?, isRecording: Bool
    ) -> Set<Int> {
        let all = Set(1..<(channelCount + 1))
        guard let recorded = isRecording ? takeAllowance?.recordedChannels : license.allowance(channelCount: channelCount, notArmed: chosen)?.recordedChannels
        else { return [] }
        return all.subtracting(recorded)
    }
}

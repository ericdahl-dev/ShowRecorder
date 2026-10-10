import Foundation

/// Free, Trial or Pro (ADR 0004, CONTEXT.md). Judged only when record is pressed, and frozen for that Take.
public enum Tier: Equatable, Sendable {
    case free
    case trial(daysLeft: Int)
    case pro
}

public enum Entitlement {
    /// How long the Trial lasts.
    public static let trialLength: TimeInterval = 14 * 86_400

    public static func tier(ownsPro: Bool, trialStartedAt: Date?, now: Date) -> Tier {
        if ownsPro { return .pro }
        guard let trialStartedAt else { return .free }
        let left = trialStartedAt.addingTimeInterval(trialLength).timeIntervalSince(now)
        guard left > 0 else { return .free }
        return .trial(daysLeft: Int((left / 86_400).rounded(.up)))
    }
}

/// What a Take pressed under a tier may do. Frozen into the Take at record press.
public struct TakeAllowance: Equatable, Sendable {
    /// The USB Channels (from 1) that get Stems. Every channel is still metered and named.
    public var recordedChannels: Set<Int>
    public var showReport: Bool
    public var reaperExport: Bool
    /// Whether typed channel names are put on the files.
    public var namingByHand: Bool
}

extension Entitlement {
    /// How many USB Channels Free records.
    public static let freeChannelCount = 2

    /// - Parameter freeChoice: the USB Channels (from 1) the operator chose to record on Free.
    public static func allowance(for tier: Tier, channelCount: Int, freeChoice: [Int]) -> TakeAllowance {
        let all = channelCount > 0 ? Set(1...channelCount) : []
        switch tier {
        case .pro, .trial:
            return TakeAllowance(recordedChannels: all, showReport: true, reaperExport: true, namingByHand: true)
        case .free:
            return TakeAllowance(recordedChannels: freeChannels(freeChoice, channelCount: channelCount), showReport: false, reaperExport: false, namingByHand: false)
        }
    }

    /// The operator's picks that exist on this input, first two only, topped up from the lowest channels.
    static func freeChannels(_ choice: [Int], channelCount: Int) -> Set<Int> {
        guard channelCount > 0 else { return [] }
        var picked: [Int] = []
        for channel in choice where (1...channelCount).contains(channel) && !picked.contains(channel) && picked.count < freeChannelCount {
            picked.append(channel)
        }
        var next = 1
        while picked.count < min(freeChannelCount, channelCount) {
            if !picked.contains(next) { picked.append(next) }
            next += 1
        }
        return Set(picked)
    }
}

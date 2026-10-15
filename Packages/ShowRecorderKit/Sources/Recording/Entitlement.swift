import Foundation

/// Free, Trial or Pro (ADR 0004, CONTEXT.md). Judged only when record is pressed, and frozen for that Take.
public enum Tier: Equatable, Sendable {
    case free
    case trial(daysLeft: Int)
    case pro

    /// How Settings names the tier.
    public var title: String {
        switch self {
        case .free: "Free"
        case .trial(let daysLeft): "14-day Trial, \(daysLeft) \(daysLeft == 1 ? "day" : "days") left"
        case .pro: "Pro"
        }
    }

    /// The Trial chip's `PowerStatus.Chip.id`, so the record screen can open the Trial sheet from it (#743).
    public static let chipID = "trial"

    /// The record screen's quiet days-left chip during the Trial; nothing on Free or Pro. It never warns.
    public var chip: PowerStatus.Chip? {
        guard case .trial(let daysLeft) = self else { return nil }
        return PowerStatus.Chip(
            text: title, shortText: "Trial · \(daysLeft) \(daysLeft == 1 ? "day" : "days")", symbol: "clock", state: .neutral,
            id: Self.chipID)
    }
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
    /// Whether the Take may also be written to the Drive: the second Copy, Repair from it, and Drive only (#705).
    public var driveCopy = true
    /// The most Markers the Take may have; nil for no limit (#705).
    public var markerLimit: Int? = nil
    /// Whether the Stems get the Mixer Link's names and colors; without it they get generic names (#705).
    public var mixerLinkNames = true
    /// Whether auto-gain may set the Mixer's preamps for this Take (#705).
    public var autoGain = true
    /// Whether clip protection may turn a clipping channel down during this Take (#705).
    public var clipProtection = true
}

extension Entitlement {
    /// How many Markers a Take may have on Free (#705).
    public static let freeMarkerLimit = 3

    /// What a Take pressed under `tier` may do. Free records every USB Channel (Eric, 2026-10-15, #705); Pro and the
    /// Trial add the rest.
    public static func allowance(for tier: Tier, channelCount: Int) -> TakeAllowance {
        let all = channelCount > 0 ? Set(1...channelCount) : []
        switch tier {
        case .pro, .trial:
            return TakeAllowance(recordedChannels: all, showReport: true, reaperExport: true, namingByHand: true)
        case .free:
            return TakeAllowance(
                recordedChannels: all, showReport: false, reaperExport: false,
                namingByHand: false, driveCopy: false, markerLimit: freeMarkerLimit, mixerLinkNames: false, autoGain: false,
                clipProtection: false)
        }
    }
}

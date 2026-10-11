import Foundation

/// How many USB Channels a Take recorded and how many carried signal, recorded or not.
public struct TakeSignal: Equatable, Sendable {
    /// A channel whose peak stayed at or below this carried no signal (an unplugged input's noise is lower).
    public static let thresholdDbfs: Double = -50

    public var recorded: Int
    public var withSignal: Int

    public init(recorded: Int, withSignal: Int) {
        self.recorded = recorded
        self.withSignal = withSignal
    }
}

/// A moment the app offers Pro (#62).
public enum ProOfferMoment: Equatable, Sendable {
    /// The first Show with a Take has ended.
    case firstShowEnded
    /// A Free Take left channels that carried signal unrecorded.
    case limitedTake(recorded: Int, withSignal: Int)
    /// The Trial's last days.
    case trialEndingSoon(daysLeft: Int)
}

/// When to offer Pro (#62, ADR 0004). Never while Pro isn't offered, never on Pro, never during a Take, and at most
/// once per Show; the first-Show offer and the Trial note come once ever. What was offered is kept on the device.
public struct ProOffers {
    private static let firstShowKey = "proOffer.firstShow"
    private static let trialNoteKey = "proOffer.trialNote"
    private static let showKey = "proOffer.show"
    /// How many Trial days left get the note.
    public static let trialNoteDays = 2

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public mutating func afterTakeStopped(show: String, signal: TakeSignal, tier: Tier, proOffered: Bool, isRecording: Bool) -> ProOfferMoment? {
        guard canOffer(in: show, tier: tier, proOffered: proOffered, isRecording: isRecording), tier == .free,
              signal.withSignal > signal.recorded else { return nil }
        offered(in: show)
        return .limitedTake(recorded: signal.recorded, withSignal: signal.withSignal)
    }

    public mutating func afterShowEnded(show: String, takeCount: Int, tier: Tier, proOffered: Bool) -> ProOfferMoment? {
        guard canOffer(in: show, tier: tier, proOffered: proOffered, isRecording: false), takeCount > 0,
              !defaults.bool(forKey: Self.firstShowKey) else { return nil }
        defaults.set(true, forKey: Self.firstShowKey)
        offered(in: show)
        return .firstShowEnded
    }

    public mutating func betweenTakes(show: String?, tier: Tier, proOffered: Bool, isRecording: Bool) -> ProOfferMoment? {
        guard case .trial(let daysLeft) = tier, daysLeft <= Self.trialNoteDays,
              canOffer(in: show, tier: tier, proOffered: proOffered, isRecording: isRecording),
              !defaults.bool(forKey: Self.trialNoteKey) else { return nil }
        defaults.set(true, forKey: Self.trialNoteKey)
        if let show { offered(in: show) }
        return .trialEndingSoon(daysLeft: daysLeft)
    }

    private func canOffer(in show: String?, tier: Tier, proOffered: Bool, isRecording: Bool) -> Bool {
        proOffered && tier != .pro && !isRecording && (show == nil || defaults.string(forKey: Self.showKey) != show)
    }

    private func offered(in show: String) {
        defaults.set(show, forKey: Self.showKey)
    }
}

/// What the paywall says (#62): why it's here, what Pro adds (ADR 0004 launch scope), the price and the Show-Safe
/// Promise in plain words. No countdowns or pressure; closing it is always one tap.
public struct Paywall: Equatable, Sendable {
    public let headline: String
    public let features = [
        "Every USB Channel, not just 2",
        "Channel names you type, on the files",
        "The Show report and Reaper export",
        "96 kHz recording",
        "Templates for each venue",
    ]
    public let promise = "A Take never stops because of a Trial, a limit or a license, and your Shows are never locked."
    public let footnote = "A one-time purchase, shared with your family through Family Sharing."
    public let buyTitle: String

    /// - Parameter proPrice: the Pro product's display price; nil until the App Store has it.
    public init(moment: ProOfferMoment?, proPrice: String?) {
        switch moment {
        case .limitedTake(let recorded, let withSignal):
            headline = "Only \(recorded) of \(withSignal) channels were recorded"
        case .firstShowEnded:
            headline = "Your first Show is recorded"
        case .trialEndingSoon(let daysLeft):
            headline = "Your 14-day Trial ends in \(daysLeft) \(daysLeft == 1 ? "day" : "days")"
        case nil:
            headline = "ShowRecorder Pro"
        }
        buyTitle = proPrice.map { "Buy Pro, \($0)" } ?? "Buy Pro"
    }
}

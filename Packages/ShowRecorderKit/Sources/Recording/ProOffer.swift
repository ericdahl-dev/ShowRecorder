import Foundation

/// How many USB Channels a Take recorded and how many carried signal, recorded or not.
public struct TakeSignal: Equatable, Sendable {
    /// A channel whose peak stayed at or below this carried no signal (an unplugged input's noise is lower).
    public static let thresholdDbfs: Double = -50

    public var recorded: Int
    public var withSignal: Int
    /// The USB Channel that peaked loudest during the Take, signal or not; nil with no channels.
    public var loudest: Loudest?

    public struct Loudest: Equatable, Sendable {
        public var usbChannel: Int
        public var peakDbfs: Double
        public init(usbChannel: Int, peakDbfs: Double) {
            self.usbChannel = usbChannel
            self.peakDbfs = peakDbfs
        }
    }

    public init(recorded: Int, withSignal: Int, loudest: Loudest? = nil) {
        self.recorded = recorded
        self.withSignal = withSignal
        self.loudest = loudest
    }
}

/// A moment the app offers Pro (#62).
public enum ProOfferMoment: Equatable, Sendable {
    /// The first Show with a Take has ended.
    case firstShowEnded
    /// A Free Take's Stems got generic names while the Mixer Link had names for them (#705).
    case genericNames
    /// The Trial's last days.
    case trialEndingSoon(daysLeft: Int)
    /// A Free Take went to the Device only while a Drive was connected (#705).
    case driveOnFree
}

/// When to offer Pro (#62, ADR 0004). Never while Pro isn't offered or the tier is unknown, never on Pro, never during a Take, and at most
/// once per Show; the first-Show offer and the Trial note come once ever. What was offered is kept on the device.
public struct ProOffers {
    private static let firstShowKey = "proOffer.firstShow"
    private static let trialNoteKey = "proOffer.trialNote"
    private static let showKey = "proOffer.show"
    private static let driveKey = "proOffer.driveOnFree"
    /// How many Trial days left get the note.
    public static let trialNoteDays = 2

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// After a Free Take whose Stems got generic names although the Mixer Link had names for them (#705): once a Show.
    /// - Parameter mixerNamed: whether the Mixer Link gave any channel a name when the Take stopped.
    public mutating func afterTakeStopped(show: String, license: License, isRecording: Bool, mixerNamed: Bool) -> ProOfferMoment? {
        guard mixerNamed, canOffer(in: show, license: license, isRecording: isRecording), license.tier == .free else { return nil }
        offered(in: show)
        return .genericNames
    }

    /// After a Free Take that went to the Device only with a Drive connected (#705): once ever, calmly, after the Take.
    public mutating func afterTakeOnDevice(show: String, license: License, isRecording: Bool, driveConnected: Bool) -> ProOfferMoment? {
        guard driveConnected, !license.allowsDrive, canOffer(in: show, license: license, isRecording: isRecording),
              !defaults.bool(forKey: Self.driveKey) else { return nil }
        defaults.set(true, forKey: Self.driveKey)
        offered(in: show)
        return .driveOnFree
    }

    public mutating func afterShowEnded(show: String, takeCount: Int, license: License) -> ProOfferMoment? {
        guard canOffer(in: show, license: license, isRecording: false), takeCount > 0,
              !defaults.bool(forKey: Self.firstShowKey) else { return nil }
        defaults.set(true, forKey: Self.firstShowKey)
        offered(in: show)
        return .firstShowEnded
    }

    public mutating func betweenTakes(show: String?, license: License, isRecording: Bool) -> ProOfferMoment? {
        guard case .trial(let daysLeft) = license.tier, daysLeft <= Self.trialNoteDays,
              canOffer(in: show, license: license, isRecording: isRecording),
              !defaults.bool(forKey: Self.trialNoteKey) else { return nil }
        defaults.set(true, forKey: Self.trialNoteKey)
        if let show { offered(in: show) }
        return .trialEndingSoon(daysLeft: daysLeft)
    }

    /// Never while Pro isn't offered, before the App Store has answered, on Pro, during a Take, or twice in a Show.
    private func canOffer(in show: String?, license: License, isRecording: Bool) -> Bool {
        guard license.proOffered, let tier = license.tier else { return false }
        return tier != .pro && !isRecording && (show == nil || defaults.string(forKey: Self.showKey) != show)
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
        "Names and colors from the Mixer, on the files",
        "Channel names you type, on the files",
        "A second Copy on a Drive, with Repair",
        "Unlimited Markers",
        "The Show report and Reaper project",
        "96 kHz recording",
        "Templates for each venue",
    ]
    public let promise = "A Take never stops because of a Trial, a limit or a license, and your Shows are never locked."
    public let footnote = "A one-time purchase, shared with your family through Family Sharing."
    public let buyTitle: String

    /// - Parameter proPrice: the Pro product's display price; nil until the App Store has it.
    public init(moment: ProOfferMoment?, proPrice: String?) {
        switch moment {
        case .genericNames:
            headline = "This Take's Stems have generic names"
        case .firstShowEnded:
            headline = "Your first Show is recorded"
        case .trialEndingSoon(let daysLeft):
            headline = "Your 14-day Trial ends in \(daysLeft) \(daysLeft == 1 ? "day" : "days")"
        case .driveOnFree:
            headline = "This Take is on the Device only"
        case nil:
            headline = "ShowRecorder Pro"
        }
        buyTitle = proPrice.map { "Buy Pro, \($0)" } ?? "Buy Pro"
    }
}

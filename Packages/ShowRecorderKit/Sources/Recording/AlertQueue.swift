/// Something the record screen tells the operator.
public struct ScreenAlert: Equatable, Identifiable, Sendable {
    /// Most urgent first.
    public enum Priority: Int, Comparable, Sendable {
        /// Recording can't start or has stopped.
        case cannotRecord
        /// A Copy stopped, or there is no Destination, during a Take.
        case destination
        /// Low battery or heat that could stop the recording.
        case power
        /// A channel shortfall or an audio interruption.
        case input
        /// How the last Take's Copies ended up.
        case copyResult
        /// A one-time hint.
        case hint

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Tone: Sendable {
        case critical, warning, ok, info
    }

    /// What tapping the alert's button does, if it has one. The app decides how.
    public enum Action: Equatable, Sendable {
        case openSystemSettings
        case dismissHint
        /// Look for the Drive again, during a Take.
        case checkDrive
        /// Get the chosen input ready again. Gets ready only; never starts a Take.
        case getReady
        /// Open the Soundcheck (#63).
        case soundcheck
        /// Hide the routing change warning (#21) until the Mixer is re-patched again.
        case dismissRoutingChange
        /// Show each Take the latest move to the Drive took up, and why one stays on this iPhone (#630).
        case showMoves
    }

    public var id: String
    public var priority: Priority
    public var tone: Tone
    public var text: String
    public var action: Action?
    /// What must change for a swiped warning to show again (#644); nil means its text.
    public var swipeKey: String?

    public init(id: String, priority: Priority, tone: Tone, text: String, action: Action? = nil, swipeKey: String? = nil) {
        self.id = id
        self.priority = priority
        self.tone = tone
        self.text = text
        self.action = action
        self.swipeKey = swipeKey
    }
}

/// The record screen has one place for alerts. It shows the most urgent and counts the rest, so a
/// pile of banners never pushes the meters or the transport around.
public struct AlertQueue: Equatable, Sendable {
    /// Every alert, most urgent first. Alerts with the same `id` appear once.
    public let ordered: [ScreenAlert]

    public init(_ alerts: [ScreenAlert]) {
        var seen = Set<String>()
        let unique = alerts.filter { seen.insert($0.id).inserted }
        // Stable: equal priorities keep the order given.
        ordered = unique.enumerated().sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }.map(\.element)
    }

    public var top: ScreenAlert? { ordered.first }
    public var others: [ScreenAlert] { Array(ordered.dropFirst()) }
    public var moreCount: Int { max(ordered.count - 1, 0) }
}

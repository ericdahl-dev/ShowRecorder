/// What the App does when the Take sequencer tells it something, in one place (#551): a Take's start, each Marker and
/// its end update the Live Activity; every end offers Pro, whoever ended the Take, except the Soundcheck's.
public struct TakeFollowUp: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let liveActivity = TakeFollowUp(rawValue: 1 << 0)
    public static let proOffer = TakeFollowUp(rawValue: 1 << 1)

    public init(_ event: TakeEvent) {
        switch event {
        case .takeStarted, .markerPlaced: self = .liveActivity
        case .takeEnded(let end): self = end.isSoundcheck ? .liveActivity : [.liveActivity, .proOffer]
        default: self = []
        }
    }
}

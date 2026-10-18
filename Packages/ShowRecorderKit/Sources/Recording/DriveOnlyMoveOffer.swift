/// What to do when a Drive connects while Drive only Takes (#196, #630) wait on the Device (#805): move them now,
/// ask the operator first, or leave them.
public enum DriveOnlyMoveOffer: Equatable, Sendable {
    case move, ask(takeCount: Int), leave

    /// Never during a Take. Where Record to isn't offered, or with Drive or Both chosen, the Takes move as before;
    /// with the Device chosen the operator is asked, once per Drive connection. Mark the connection asked only on `ask`:
    /// a Drive that connects during a Take is asked about after Stop.
    /// - Parameter storedChoice: the setting as saved (`RecordToSetting.load()`), not `atPress`: Free records to the
    ///   Device whatever is chosen, and its Takes still move as before.
    public static func decide(storedChoice choice: RecordTo, isOffered: Bool, isRecording: Bool, waitingTakes: Int,
                              askedThisConnection: Bool) -> DriveOnlyMoveOffer {
        guard !isRecording, waitingTakes > 0 else { return .leave }
        guard isOffered, choice == .device else { return .move }
        return askedThisConnection ? .leave : .ask(takeCount: waitingTakes)
    }

    /// The question for `ask`.
    /// - Parameter deviceWord: the device the app runs on (iPhone, iPad or Mac).
    public static func question(takeCount: Int, deviceWord: String) -> String {
        takeCount == 1
            ? "1 Take recorded for the Drive is on this \(deviceWord). Move it to the Drive now?"
            : "\(takeCount) Takes recorded for the Drive are on this \(deviceWord). Move them to the Drive now?"
    }

    /// The answer that moves the Takes now.
    public static let moveLabel = "Move"
    /// The answer that leaves them on the Device until the next Drive connection.
    public static let notNowLabel = "Not now"
}

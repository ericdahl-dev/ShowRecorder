/// How a running Take is stopped from the record screen (#753). The iPhone and iPad hold the Stop button where
/// `HoldToStopAvailability` allows; everywhere else, and always on the Mac, it is a tap or click and a confirmation.
public enum TakeStopStyle: Equatable, Sendable {
    case hold, confirm

    public static func resolve(isIOS: Bool, holdToStopAvailable: Bool) -> TakeStopStyle {
        isIOS && holdToStopAvailable ? .hold : .confirm
    }

    /// The answer for the running app. `isIOS` is false on the Mac, which keeps click and confirm.
    public static func current(isIOS: Bool) -> TakeStopStyle {
        resolve(isIOS: isIOS, holdToStopAvailable: HoldToStopAvailability.isAvailableInThisBuild)
    }
}

/// How a running Take is stopped from the record screen (#753). The iPhone holds the Stop button where
/// `HoldToStopAvailability` allows; everywhere else, and always on the Mac, it is a tap or click and a confirmation.
public enum TakeStopStyle: Equatable, Sendable {
    case hold, confirm

    public static func resolve(isPhone: Bool, holdToStopAvailable: Bool) -> TakeStopStyle {
        isPhone && holdToStopAvailable ? .hold : .confirm
    }

    /// The answer for the running app. `isPhone` is false on iPad and the Mac, which keep tap and confirm.
    public static func current(isPhone: Bool) -> TakeStopStyle {
        resolve(isPhone: isPhone, holdToStopAvailable: HoldToStopAvailability.isAvailableInThisBuild)
    }
}

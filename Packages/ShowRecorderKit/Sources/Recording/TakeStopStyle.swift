/// How a running Take is stopped from the record screen (#753). The iPhone holds the Stop button where
/// `HoldToStopAvailability` allows, the iPad where `HoldToStopOnIPadAvailability` allows; everywhere else, and always on
/// the Mac, it is a tap or click and a confirmation.
public enum TakeStopStyle: Equatable, Sendable {
    case hold, confirm

    /// The hardware the record screen runs on.
    public enum Device: Equatable, Sendable {
        case iPhone, iPad, mac
    }

    public static func resolve(device: Device, holdOnIPhone: Bool, holdOnIPad: Bool) -> TakeStopStyle {
        switch device {
        case .iPhone: holdOnIPhone ? .hold : .confirm
        case .iPad: holdOnIPad ? .hold : .confirm
        case .mac: .confirm
        }
    }

    /// The answer for the running app.
    public static func current(device: Device) -> TakeStopStyle {
        resolve(
            device: device,
            holdOnIPhone: HoldToStopAvailability.isAvailableInThisBuild,
            holdOnIPad: HoldToStopOnIPadAvailability.isAvailableInThisBuild
        )
    }
}

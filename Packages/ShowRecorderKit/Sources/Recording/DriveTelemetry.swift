import Destinations
import Telemetry

/// Usage events from the Drive (ADR 0007, #1026): drive_connected when the Drive becomes available, drive_lost when an
/// available Drive becomes unavailable. The app feeds it every Drive status it reads; a re-read that finds the same
/// state (free space changes, another folder on a Drive that is there) sends nothing. The first status is where it
/// starts, so a Drive already there at launch isn't a connect.
@MainActor
public final class DriveTelemetry {
    private let send: (TelemetryEvent) -> Void
    private var wasAvailable: Bool?

    public init(send: @escaping (TelemetryEvent) -> Void) {
        self.send = send
    }

    public func observe(_ status: DriveStatus) {
        let isAvailable: Bool
        let isLost: Bool
        switch status {
        case .available: (isAvailable, isLost) = (true, false)
        case .unavailable: (isAvailable, isLost) = (false, true)
        case .notChosen: (isAvailable, isLost) = (false, false)
        }
        defer { wasAvailable = isAvailable }
        guard let wasAvailable else { return }
        if isAvailable, !wasAvailable { send(.driveConnected) }
        if isLost, wasAvailable { send(.driveLost) }
    }
}

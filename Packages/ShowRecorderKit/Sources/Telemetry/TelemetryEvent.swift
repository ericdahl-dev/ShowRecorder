import Foundation

/// The fixed list of usage events (ADR 0007). Counts and kinds only: never Show names, venues or notes, Channel
/// names, Template names, audio or file paths. A new event is a new case here, so the list stays reviewable.
public enum TelemetryEvent: Equatable, Sendable {
    case appOpened
    /// `mixerFamily` is the Mixer family's raw value when the Mixer Link is connected, else nil.
    case takeStarted(channelCount: Int, destinations: TelemetryDestinations, mixerFamily: String?)
    case takeStopped(seconds: Int, channelCount: Int, dropouts: Int, cause: TakeStopCause)
    case showCreated
    case showDeleted
    case driveConnected
    case driveLost
    case mixerLinkConnected(mixerFamily: String)
    case trialStarted
    case proBought

    public var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .takeStarted: "take_started"
        case .takeStopped: "take_stopped"
        case .showCreated: "show_created"
        case .showDeleted: "show_deleted"
        case .driveConnected: "drive_connected"
        case .driveLost: "drive_lost"
        case .mixerLinkConnected: "mixer_link_connected"
        case .trialStarted: "trial_started"
        case .proBought: "pro_bought"
        }
    }

    public var properties: [String: TelemetryValue] {
        switch self {
        case let .takeStarted(channelCount, destinations, mixerFamily):
            var properties: [String: TelemetryValue] = [
                "channel_count": .int(channelCount), "destinations": .string(destinations.rawValue),
            ]
            if let mixerFamily { properties["mixer_family"] = .string(mixerFamily) }
            return properties
        case let .takeStopped(seconds, channelCount, dropouts, cause):
            return [
                "seconds": .int(seconds), "channel_count": .int(channelCount), "dropouts": .int(dropouts),
                "cause": .string(cause.rawValue),
            ]
        case let .mixerLinkConnected(mixerFamily):
            return ["mixer_family": .string(mixerFamily)]
        case .appOpened, .showCreated, .showDeleted, .driveConnected, .driveLost, .trialStarted, .proBought:
            return [:]
        }
    }
}

/// An event property's value.
public enum TelemetryValue: Equatable, Sendable {
    case int(Int)
    case string(String)
    case bool(Bool)
}

/// Where a Take was written: the "Record to" choice.
public enum TelemetryDestinations: String, Sendable {
    case device
    case driveOnly = "drive_only"
    case both
}

/// What ended a Take.
public enum TakeStopCause: String, Sendable {
    /// Stop on the iPhone, iPad or Mac.
    case operatorStop = "operator"
    /// Stop from the Apple Watch.
    case watch
    /// Anything else, such as the app being closed.
    case other
}

/// A failure the app caught on purpose (the Show-Safe Promise), reported with an explicit call at each branch. Keeps
/// the error's type, domain and code, never its message: a message can hold a file path, and a path holds Show names.
public struct TelemetryFailure: Equatable, Sendable {
    public enum Area: String, CaseIterable, Sendable {
        case driveWrite = "drive_write"
        case repair
        case moveToDrive = "move_to_drive"
        case deleteShow = "delete_show"
    }

    public let area: Area
    public let errorType: String
    public let domain: String
    public let code: Int

    public init(area: Area, error: any Error) {
        let nsError = error as NSError
        self.area = area
        errorType = String(describing: type(of: error))
        domain = nsError.domain
        code = nsError.code
    }

    /// One line for the issue title, e.g. "drive_write: CocoaError NSCocoaErrorDomain 640".
    public var summary: String { "\(area.rawValue): \(errorType) \(domain) \(code)" }
}

import Foundation

/// What the watch shows of the recorder (#100): Armed, Recording with its start time, and anything that needs
/// attention. The iPhone sends it whenever it changes; the watch holds nothing else.
public struct WatchStatus: Codable, Equatable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        /// No Audio interface is Armed: the watch can't Start (the iPhone can't open the mic from the background).
        case notArmed
        case armed
        case recording(startedAt: Date, takeTitle: String, markerCount: Int)
    }

    /// Something that needs attention, shown as a symbol and a few words so it reads without color. Not the whole
    /// banner set from the record screen.
    public enum Problem: String, Codable, CaseIterable, Sendable {
        case deviceLowSpace, driveLowSpace, copyStopped, gapOrDropout, mixerLinkLost

        /// An SF Symbol name.
        public var symbol: String {
            switch self {
            case .deviceLowSpace: "iphone.gen3"
            case .driveLowSpace: "externaldrive.badge.exclamationmark"
            case .copyStopped: "doc.on.doc"
            case .gapOrDropout: "waveform.badge.exclamationmark"
            case .mixerLinkLost: "slider.horizontal.3"
            }
        }

        public var text: String {
            switch self {
            case .deviceLowSpace: "iPhone low on space"
            case .driveLowSpace: "Drive low on space"
            case .copyStopped: "A Copy stopped"
            case .gapOrDropout: "Gap or Dropout"
            case .mixerLinkLost: "Mixer Link lost"
            }
        }
    }

    /// The message's shape. A watch app a version behind still reads what it knows of a newer one.
    public static let currentVersion = 1

    public var version = Self.currentVersion
    /// The iPhone's clock when it sent this, so the watch stamps commands in the iPhone's time.
    public var sentAt: Date
    public var state: State
    public var problems: [Problem]

    public init(state: State, problems: [Problem] = [], sentAt: Date = .now) {
        self.state = state
        self.problems = problems
        self.sentAt = sentAt
    }
}

extension WatchStatus {
    private enum CodingKeys: String, CodingKey { case version, sentAt, state, problems }

    /// Problems a newer iPhone knows and this watch doesn't are left out, rather than failing the whole status.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        sentAt = try container.decodeIfPresent(Date.self, forKey: .sentAt) ?? .distantPast
        state = try container.decode(State.self, forKey: .state)
        problems = try container.decode([String].self, forKey: .problems).compactMap(Problem.init(rawValue:))
    }
}

/// WatchConnectivity carries property-list dictionaries. Each message is one entry, its kind as the key and its JSON
/// as the value, so either side can tell what it got.
public protocol WatchMessage: Codable {
    static var key: String { get }
}

public struct WatchMessageError: Error, Equatable {
    public let expected: String
}

extension WatchMessage {
    public var message: [String: Any] {
        [Self.key: (try? JSONEncoder().encode(self)) ?? Data()]
    }

    public init(message: [String: Any]) throws {
        guard let data = message[Self.key] as? Data else { throw WatchMessageError(expected: Self.key) }
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}

extension WatchStatus: WatchMessage { public static let key = "status" }
extension WatchCommand: WatchMessage { public static let key = "command" }
extension WatchReply: WatchMessage { public static let key = "reply" }

import Foundation

/// One of the three things the watch can ask of the recorder (#100). Each has its own id, so a command the link
/// delivers twice runs once, and its time, so one that arrives late is dropped rather than replayed.
public struct WatchCommand: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case start, stop, marker
    }

    public var id: UUID
    public var kind: Kind
    public var sentAt: Date

    public init(id: UUID = UUID(), kind: Kind, sentAt: Date) {
        self.id = id
        self.kind = kind
        self.sentAt = sentAt
    }
}

/// The recorder's answer to a command.
public enum WatchReply: Codable, Equatable, Sendable {
    /// Done: the Take started or stopped, or the Marker is in.
    case done
    /// Not done, and why, in words for the wrist.
    case refused(String)
    /// It arrived too late to act on (the link was down), so nothing happened.
    case tooLate

    /// What a watch shows for an answer from a newer iPhone that it doesn't know.
    public static let updateText = "Update ShowRecorder on your watch"
}

extension WatchReply {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Reads the shape Swift writes for this enum; an answer this version doesn't know reads as a refusal saying to
    /// update, rather than failing and looking like a lost link.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if container.contains(Key(stringValue: "done")) {
            self = .done
        } else if container.contains(Key(stringValue: "tooLate")) {
            self = .tooLate
        } else if container.contains(Key(stringValue: "refused")) {
            let reason = try container.nestedContainer(keyedBy: Key.self, forKey: Key(stringValue: "refused"))
            self = .refused(try reason.decode(String.self, forKey: Key(stringValue: "_0")))
        } else {
            self = .refused(Self.updateText)
        }
    }
}
